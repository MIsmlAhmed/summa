! SUMMA - Structure for Unifying Multiple Modeling Alternatives
! Copyright (C) 2014-2020 NCAR/RAL; University of Saskatchewan; University of Washington
!
! This file is part of SUMMA
!
! For more information see: http://www.ral.ucar.edu/projects/summa
!
! This program is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.

module run_oneGRU_module

! numerical recipes data types
USE nrtype

! access integers to define "yes" and "no"
USE globalData,only:yes,no             ! .true. and .false.

! define data types
USE data_types,only:&
                    ! GRU-to-HRU mapping
                    gru2hru_map,     & ! HRU info
                    ! no spatial dimension
                    var_ilength,     & ! x%var(:)%dat        (i4b)
                    var_dlength,     & ! x%var(:)%dat        (dp)
                    var_d,           & ! var(:)              ! for GRU parameters
                    ! hru dimension
                    hru_int,         & ! x%hru(:)%var(:)     (i4b)
                    hru_int8,        & ! x%hru(:)%var(:)     integer(8)
                    hru_double,      & ! x%hru(:)%var(:)     (dp)
                !     gru_double,      & ! x%gru(:)%var(:)     (dp)
                    hru_intVec,      & ! x%hru(:)%var(:)%dat (i4b)
                    hru_doubleVec      ! x%hru(:)%var(:)%dat (dp)

! provide access to the named variables that describe elements of parameter structures
USE var_lookup,only:iLookTYPE          ! look-up values for classification of veg, soils etc.
USE var_lookup,only:iLookID            ! look-up values for hru and gru IDs
USE var_lookup,only:iLookATTR          ! look-up values for local attributes
USE var_lookup,only:iLookINDEX         ! look-up values for local column index variables
USE var_lookup,only:iLookFLUX          ! look-up values for local column model fluxes
USE var_lookup,only:iLookBVAR          ! look-up values for basin-average model variables
USE var_lookup,only:iLookBPAR          ! look-up values for basin-average model parameters (for HDS)
USE var_lookup, only:iLookFORCE        ! look-up values for HRU forcing - used to estimate basin average forcing for HDS

! provide access to model decisions
USE globalData,only:model_decisions    ! model decision structure
USE var_lookup,only:iLookDECISIONS     ! look-up values for model decisions

! global data
USE globalData,only:data_step              ! time step of forcing data (s) - used by HDS to accumulate fluxes

! provide access to the named variables that describe model decisions
USE mDecisions_module,only:&           ! look-up values for the choice of method for the spatial representation of groundwater
 localColumn, &                        ! separate groundwater representation in each local soil column
 singleBasin, &                        ! single groundwater store over the entire basin
 bigBucket                             ! a big bucket (lumped aquifer model)

! -----------------------------------------------------------------------------------------------------------------------------------
! -----------------------------------------------------------------------------------------------------------------------------------
! -----------------------------------------------------------------------------------------------------------------------------------
implicit none
private
public::run_oneGRU

contains

 ! ************************************************************************************************
 ! public subroutine run_oneGRU: simulation for a single GRU
 ! ************************************************************************************************

 ! simulation for a single GRU
 subroutine run_oneGRU(&
                       ! model control
                       gruInfo,            & ! intent(inout): HRU information for given GRU (# HRUs, #snow+soil layers)
                       dt_init,            & ! intent(inout): used to initialize the length of the sub-step for each HRU
                       ixComputeVegFlux,   & ! intent(inout): flag to indicate if we are computing fluxes over vegetation (false=no, true=yes)
                       ! data structures (input)
                       timeVec,            & ! intent(in):    model time data
                       typeHRU,            & ! intent(in):    local classification of soil veg etc. for each HRU
                       idHRU,              & ! intent(in):    local classification of hru and gru IDs
                       attrHRU,            & ! intent(in):    local attributes for each HRU
                       bparGRU,            & ! intent(in):    local attributes for the GRU for HDS calculations
                       ! data structures (input-output)
                       mparHRU,            & ! intent(inout):    local model parameters
                       indxHRU,            & ! intent(inout): model indices
                       forcHRU,            & ! intent(inout): model forcing data
                       progHRU,            & ! intent(inout): prognostic variables for a local HRU
                       diagHRU,            & ! intent(inout): diagnostic variables for a local HRU
                       fluxHRU,            & ! intent(inout): model fluxes for a local HRU
                       bvarData,           & ! intent(inout): basin-average variables
                       ! error control
                       err,message)          ! intent(out):   error control

 ! ----- define downstream subroutines -----------------------------------------------------------------------------------

 USE run_oneHRU_module,only:run_oneHRU                       ! module to run for one HRU
 USE qTimeDelay_module,only:qOverland                        ! module to route water through an "unresolved" river network
 USE HDS                                                     ! module to run HDS pothole storage dynamics

 ! ----- define dummy variables ------------------------------------------------------------------------------------------

 implicit none

 ! model control
 type(gru2hru_map)   , intent(inout) :: gruInfo              ! HRU information for given GRU (# HRUs, #snow+soil layers)
 real(rkind)            , intent(inout) :: dt_init(:)        ! used to initialize the length of the sub-step for each HRU
 integer(i4b)        , intent(inout) :: ixComputeVegFlux(:)  ! flag to indicate if we are computing fluxes over vegetation (false=no, true=yes)
 ! data structures (input)
 integer(i4b)        , intent(in)    :: timeVec(:)           ! integer vector      -- model time data
 type(hru_int)       , intent(in)    :: typeHRU              ! x%hru(:)%var(:)     -- local classification of soil veg etc. for each HRU
 type(hru_int8)      , intent(in)    :: idHRU                ! x%hru(:)%var(:)     -- local classification of hru and gru IDs
 type(hru_double)    , intent(in)    :: attrHRU              ! x%hru(:)%var(:)     -- local attributes for each HRU
 type(var_d)         , intent(in)    :: bparGRU              ! x%gru(:)%var(:)     -- basin-average parameters
 ! data structures (input-output)
 type(hru_doubleVec) , intent(inout) :: mparHRU              ! x%hru(:)%var(:)%dat -- local (HRU) model parameters
 type(hru_intVec)    , intent(inout) :: indxHRU              ! x%hru(:)%var(:)%dat -- model indices
 type(hru_double)    , intent(inout) :: forcHRU              ! x%hru(:)%var(:)     -- model forcing data
 type(hru_doubleVec) , intent(inout) :: progHRU              ! x%hru(:)%var(:)%dat -- model prognostic (state) variables
 type(hru_doubleVec) , intent(inout) :: diagHRU              ! x%hru(:)%var(:)%dat -- model diagnostic variables
 type(hru_doubleVec) , intent(inout) :: fluxHRU              ! x%hru(:)%var(:)%dat -- model fluxes
 type(var_dlength)   , intent(inout) :: bvarData             ! x%var(:)%dat        -- basin-average variables
 ! error control
 integer(i4b)        , intent(out)   :: err                  ! error code
 character(*)        , intent(out)   :: message              ! error message

 ! ----- define local variables ------------------------------------------------------------------------------------------

 ! general local variables
 character(len=256)                      :: cmessage               ! error message
 integer(i4b)                            :: iHRU                   ! HRU index
 integer(i4b)                            :: jHRU,kHRU              ! index of the hydrologic response unit
 integer(i4b)                            :: nSnow                  ! number of snow layers
 integer(i4b)                            :: nSoil                  ! number of soil layers
 integer(i4b)                            :: nLayers                ! total number of layers
 real(rkind)                             :: fracHRU                ! fractional area of a given HRU (-)
 logical(lgt)                            :: computeVegFluxFlag     ! flag to indicate if we are computing fluxes over vegetation (.false. means veg is buried with snow)
 ! HDS local variables
 real(rkind)                             :: basinPrecip            ! average basin precipitation amount (kg m-2 s-1 = mm s-1)
 real(rkind)                             :: basinPotentialEvap     ! average basin potential evaporation amount (mm s-1)
 real(rkind)                             :: depressionArea         ! depression area (m2)
 real(rkind)                             :: depressionVol          ! depression volume (m3)
 real(rkind)                             :: landArea               ! land area = total area - depression area (m2)
 real(rkind)                             :: upslopeArea            ! upstram area (area that contributes to the depressions) (m2)
 real(rkind)                             :: Q_det_adj, Q_dix_adj   ! adjusted evapotranspiration & infiltration fluxes [L3 T-1] for mass balance closure (i.e., when losses > pondVol); currently not used
 ! initialize error control
 err=0; write(message, '(A24,I0,A2)' ) 'run_oneGRU (gru index = ',gruInfo%gru_nc,')/'

 ! ----- basin initialization --------------------------------------------------------------------------------------------

 ! initialize runoff variables
 bvarData%var(iLookBVAR%basin__SurfaceRunoff)%dat(1)    = 0._rkind  ! surface runoff (m s-1)
 bvarData%var(iLookBVAR%basin__SoilDrainage)%dat(1)     = 0._rkind  ! soil drainage (m s-1)
 bvarData%var(iLookBVAR%basin__ColumnOutflow)%dat(1)    = 0._rkind  ! outflow from all "outlet" HRUs (those with no downstream HRU)
 bvarData%var(iLookBVAR%basin__TotalRunoff)%dat(1)      = 0._rkind  ! total runoff to the channel from all active components (m s-1)

 ! initialize baseflow variables
 bvarData%var(iLookBVAR%basin__AquiferRecharge)%dat(1)  = 0._rkind ! recharge to the aquifer (m s-1)
 bvarData%var(iLookBVAR%basin__AquiferBaseflow)%dat(1)  = 0._rkind ! baseflow from the aquifer (m s-1)
 bvarData%var(iLookBVAR%basin__AquiferTranspire)%dat(1) = 0._rkind ! transpiration loss from the aquifer (m s-1)

 ! initialize basin average forcing
 basinPrecip = 0._rkind     ! precipitation rate averaged over the basin
 basinPotentialEvap = 0._rkind

 ! initialize total inflow for each layer in a soil column
 do iHRU=1,gruInfo%hruCount
  fluxHRU%hru(iHRU)%var(iLookFLUX%mLayerColumnInflow)%dat(:) = 0._rkind
 end do

 ! ***********************************************************************************************************************
 ! ********** RUN FOR ONE HRU ********************************************************************************************
 ! ***********************************************************************************************************************

 ! loop through HRUs
 do iHRU=1,gruInfo%hruCount

  ! ----- hru initialization ---------------------------------------------------------------------------------------------

  ! update the number of layers
  nSnow   = indxHRU%hru(iHRU)%var(iLookINDEX%nSnow)%dat(1)    ! number of snow layers
  nSoil   = indxHRU%hru(iHRU)%var(iLookINDEX%nSoil)%dat(1)    ! number of soil layers
  nLayers = indxHRU%hru(iHRU)%var(iLookINDEX%nLayers)%dat(1)  ! total number of layers

  ! set the flag to compute the vegetation flux
  computeVegFluxFlag = (ixComputeVegFlux(iHRU) == yes)

  ! ----- run the model --------------------------------------------------------------------------------------------------

  ! simulation for a single HRU
  call run_oneHRU(&
                  ! model control
                  gruInfo%hruInfo(iHRU)%hru_id,    & ! intent(in):    hruId
                  dt_init(iHRU),                   & ! intent(inout): initial time step
                  computeVegFluxFlag,              & ! intent(inout): flag to indicate if we are computing fluxes over vegetation (false=no, true=yes)
                  nSnow,nSoil,nLayers,             & ! intent(inout): number of snow and soil layers
                  ! data structures (input)
                  timeVec,                         & ! intent(in):    model time data
                  typeHRU%hru(iHRU),               & ! intent(in):    local classification of soil veg etc. for each HRU
                  attrHRU%hru(iHRU),               & ! intent(in):    local attributes for each HRU
                  bvarData,                        & ! intent(in):    basin-average model variables
                  ! data structures (input-output)
                  mparHRU%hru(iHRU),               & ! intent(inout): model parameters
                  indxHRU%hru(iHRU),               & ! intent(inout): model indices
                  forcHRU%hru(iHRU),               & ! intent(inout): model forcing data
                  progHRU%hru(iHRU),               & ! intent(inout): model prognostic variables for a local HRU
                  diagHRU%hru(iHRU),               & ! intent(inout): model diagnostic variables for a local HRU
                  fluxHRU%hru(iHRU),               & ! intent(inout): model fluxes for a local HRU
                  ! error control
                  err,cmessage)                      ! intent(out):   error control
  if(err/=0)then; err=20; message=trim(message)//trim(cmessage); return; endif

  ! update layer numbers that could be changed in run_oneHRU -- needed for model output
  gruInfo%hruInfo(iHRU)%nSnow = nSnow
  gruInfo%hruInfo(iHRU)%nSoil = nSoil

  ! save the flag for computing the vegetation fluxes
  if(computeVegFluxFlag)       ixComputeVegFlux(iHRU) = yes
  if(.not. computeVegFluxFlag) ixComputeVegFlux(iHRU) = no

  ! identify the area covered by the current HRU
  fracHRU = attrHRU%hru(iHRU)%var(iLookATTR%HRUarea) / bvarData%var(iLookBVAR%basin__totalArea)%dat(1)
  ! (Note:  for efficiency, this could this be done as a setup task, not every timestep)

  ! ----- compute fluxes across HRUs --------------------------------------------------------------------------------------------------

  ! identify lateral connectivity
  ! (Note:  for efficiency, this could this be done as a setup task, not every timestep)
  kHRU = 0
  ! identify the downslope HRU
  dsHRU: do jHRU=1,gruInfo%hruCount
   if(typeHRU%hru(iHRU)%var(iLookTYPE%downHRUindex) == idHRU%hru(jHRU)%var(iLookID%hruId))then
    if(kHRU==0)then  ! check there is a unique match
     kHRU=jHRU
     exit dsHRU
    end if  ! (check there is a unique match)
   end if  ! (if identified a downslope HRU)
  end do dsHRU

  ! if lateral flows are active, add inflow to the downslope HRU
  if(kHRU > 0)then  ! if there is a downslope HRU
   fluxHRU%hru(kHRU)%var(iLookFLUX%mLayerColumnInflow)%dat(:) = fluxHRU%hru(kHRU)%var(iLookFLUX%mLayerColumnInflow)%dat(:)  + fluxHRU%hru(iHRU)%var(iLookFLUX%mLayerColumnOutflow)%dat(:)

  ! otherwise just increment basin (GRU) column outflow (m3 s-1) with the hru fraction
  else
   bvarData%var(iLookBVAR%basin__ColumnOutflow)%dat(1) = bvarData%var(iLookBVAR%basin__ColumnOutflow)%dat(1) + sum(fluxHRU%hru(iHRU)%var(iLookFLUX%mLayerColumnOutflow)%dat(:))
  end if

  ! ----- calculate weighted basin (GRU) fluxes --------------------------------------------------------------------------------------

  ! increment basin surface runoff (m s-1)
  bvarData%var(iLookBVAR%basin__SurfaceRunoff)%dat(1)  = bvarData%var(iLookBVAR%basin__SurfaceRunoff)%dat(1) + fluxHRU%hru(iHRU)%var(iLookFLUX%scalarSurfaceRunoff)%dat(1) * fracHRU

  ! increment basin soil drainage (m s-1)
  bvarData%var(iLookBVAR%basin__SoilDrainage)%dat(1)   = bvarData%var(iLookBVAR%basin__SoilDrainage)%dat(1)  + fluxHRU%hru(iHRU)%var(iLookFLUX%scalarSoilDrainage)%dat(1)  * fracHRU

  ! increment aquifer variables -- ONLY if aquifer baseflow is computed individually for each HRU and aquifer is run
  ! NOTE: groundwater computed later for singleBasin
  if(model_decisions(iLookDECISIONS%spatial_gw)%iDecision == localColumn .and. model_decisions(iLookDECISIONS%groundwatr)%iDecision == bigBucket) then

   bvarData%var(iLookBVAR%basin__AquiferRecharge)%dat(1)  = bvarData%var(iLookBVAR%basin__AquiferRecharge)%dat(1)   + fluxHRU%hru(iHRU)%var(iLookFLUX%scalarSoilDrainage)%dat(1)     * fracHRU
   bvarData%var(iLookBVAR%basin__AquiferTranspire)%dat(1) = bvarData%var(iLookBVAR%basin__AquiferTranspire)%dat(1)  + fluxHRU%hru(iHRU)%var(iLookFLUX%scalarAquiferTranspire)%dat(1) * fracHRU
   bvarData%var(iLookBVAR%basin__AquiferBaseflow)%dat(1)  =  bvarData%var(iLookBVAR%basin__AquiferBaseflow)%dat(1)  &
           +  fluxHRU%hru(iHRU)%var(iLookFLUX%scalarAquiferBaseflow)%dat(1) * fracHRU
  end if

  ! averaging more fluxes (and/or states) can be added to this section as desired
  basinPrecip = basinPrecip + (forcHRU%hru(iHRU)%var(iLookFORCE%pptrate) * fracHRU)
  basinPotentialEvap = 0._rkind
 end do  ! (looping through HRUs)

 ! ***********************************************************************************************************************
 ! ********** END LOOP THROUGH HRUS **************************************************************************************
 ! ***********************************************************************************************************************
 ! perform the pothole storage and routing
 associate(totalArea      => bvarData%var(iLookBVAR%basin__totalArea)%dat(1) , &
           basinTotalRunoff => bvarData%var(iLookBVAR%basin__TotalRunoff)%dat(1) , &  ! basin total runoff (m s-1)
          ! HDS pothole storage variables
           vMin           =>    bvarData%var(iLookBVAR%vMin)%dat(1)             , &   ! volume of water in the meta depression at the start of a fill period (m3)
           conAreaFrac    =>    bvarData%var(iLookBVAR%conAreaFrac)%dat(1)      , &   ! fractional contributing area (-)
           pondVolFrac    =>    bvarData%var(iLookBVAR%pondVolFrac)%dat(1)      , &   ! fractional pond volume = pondVol/depressionVol (-)
           pondVol        =>    bvarData%var(iLookBVAR%pondVol)%dat(1)          , &   ! pond volume at the end of time step (m3)
           pondArea       =>    bvarData%var(iLookBVAR%pondArea)%dat(1)         , &   ! pond area at the end of the time step (m2)
           pondOutflow    =>    bvarData%var(iLookBVAR%pondOutflow)%dat(1)      , &   ! pond outflow (m3)
           ! HDS pothole storage parameters
           depressionDepth => bparGRU%var(iLookBPAR%depressionDepth)                 , &
           depressionAreaFrac => bparGRU%var(iLookBPAR%depressionAreaFrac)           , &
           depressionCatchAreaFrac => bparGRU%var(iLookBPAR%depressionCatchAreaFrac) , &
           depression_p =>  bparGRU%var(iLookBPAR%depression_p)                      , &
           depression_b => bparGRU%var(iLookBPAR%depression_p)                         &
        )

 ! compute water balance for the basin aquifer
 if(model_decisions(iLookDECISIONS%spatial_gw)%iDecision == singleBasin)then
  message=trim(message)//'multi_driver/bigBucket groundwater code not transferred from old code base yet'
  err=20; return
 end if

 ! calculate total runoff depending on whether aquifer is connected
 if(model_decisions(iLookDECISIONS%groundwatr)%iDecision == bigBucket) then
  ! aquifer
  basinTotalRunoff = bvarData%var(iLookBVAR%basin__SurfaceRunoff)%dat(1) + bvarData%var(iLookBVAR%basin__ColumnOutflow)%dat(1)/totalArea + bvarData%var(iLookBVAR%basin__AquiferBaseflow)%dat(1)
 else
  ! no aquifer
  basinTotalRunoff = bvarData%var(iLookBVAR%basin__SurfaceRunoff)%dat(1) + bvarData%var(iLookBVAR%basin__ColumnOutflow)%dat(1)/totalArea + bvarData%var(iLookBVAR%basin__SoilDrainage)%dat(1)
 endif

 ! ***********************************************************************************************************************
 ! ********** PRAIRIE POTHOLE IMPLEMENTATION (HDS)************************************************************************
 ! ***********************************************************************************************************************

 ! initialize pondOutflow
 pondOutflow = 0._rkind
 ! calculate some spatial attributes (should be moved somewhere else)
 depressionArea = depressionAreaFrac * totalArea
 depressionVol = depressionDepth * depressionArea
 landArea = totalArea - depressionArea
 upslopeArea = max(landArea * depressionCatchAreaFrac, 0._rkind)
!  write(*,*) data_step
 ! run the actual HDS depressional storage model (currently catchfrac is not accounted for)
 call runDepression(&
                    ! subroutine inputs and parameters
                    pondVol                                                                , &    ! input/output:  state variable = pond volume [m3]
                    basinTotalRunoff * 0.001 * data_step                                   , &    ! forcing data       = runoff                [m s-1] -> mm/timestep
                    basinPrecip * 0.001 * data_step                                        , &    ! forcing data       = precipitation         [m s-1] -> mm/timestep
                    basinPotentialEvap * 0.001 * data_step                                 , &    ! forcing data       = potential evaporation [m s-1] -> mm/timestep
                    depressionArea                                                         , &    ! spatial attributes = depression area       [m2]
                    depressionVol                                                          , &    ! spatial attributes = depression volume     [m3]
                    upslopeArea                                                            , &    ! spatial attributes = upstream area         [m2]
                    depression_p                                                           , &    ! model parameters   = p shape of the slope profile [-]
                    0._rkind                                                               , &    ! model parameters   = tau  time constant linear reservoir [day-1] ! currently deactivated
                    depression_b                                                           , &    ! model parameters   = b shape of contributing fraction curve [-]
                    vMin                                                                   , &    ! model parameters   = vmin minimum volume [m3]
                    1._rkind                                                               , &    ! model time step [length of timestep = 1]
                    ! outputs
                    Q_det_adj, Q_dix_adj                                                   , &    ! adjusted evapotranspiration & infiltration fluxes [L3 T-1] for mass balance closure (i.e., when losses > pondVol)
                    pondVolFrac, conAreaFrac                                               , &    ! fractional volume [-], fractional contributing area [-]
                    pondArea, pondOutflow)                                                        ! pond area at the end of the time step [m2], pond outflow [m3]    
!  depressionArea = depressionAreaFrac * totalArea
!  depressionVol = depressionDepth * depressionArea
!  pondVol = pondVolFrac * depressionVol
!  landArea = totalArea - depressionArea(n)
!  upslopeArea = max(landArea * depressionCatchAreaFrac, zero)
!  precip = 0.0
!  pot_evap = 0.0
!  runoff_depth = basinTotalRunoff
!  call runDepression(pondVol,                                             &    ! input/output:  state variable = pond volume [m3]
!                     runoff_depth, precip, pot_evap,                         &    ! input:         forcing data = runoff, precipitation, ET [mm/day]
!                     depressionArea(n), depressionVol(n), upslopeArea, &    ! input:         spatial attributes = depression area [m2], depression volume [m3], upstream area [m2]
!                     p(n), tau,                                              &    ! input:         model parameters = p [-] shape of the slope profile; tau [day-1] time constant linear reservoir
!                     b(n), vMin,                                          &    ! input:         model parameters = b [-] shape of contributing fraction curve; vmin [m3] minimum volume
!                     dt,                                                     &    ! input:         model time step [days]
!                     Q_det_adj, Q_dix_adj,                                   &    ! output:        adjusted evapotranspiration & infiltration fluxes [L3 T-1] for mass balance closure (i.e., when losses > pondVol)
!                     pondVolFrac, conAreaFrac,                             &    ! output:        fractional volume [-], fractional contributing area [-]
!                     pondArea, pondOutflow)                              ! output:        pond area at the end of the time step [m2], pond outflow [m3]    


  ! ***********************************************************************************************************************                                               
                                                
 call qOverland(&
                ! input
                model_decisions(iLookDECISIONS%subRouting)%iDecision,          &  ! intent(in): index for routing method
                basinTotalRunoff,                                              &  ! intent(in): total runoff to the channel from all active components (m s-1)
                bvarData%var(iLookBVAR%routingFractionFuture)%dat,             &  ! intent(in): fraction of runoff in future time steps (m s-1)
                bvarData%var(iLookBVAR%routingRunoffFuture)%dat,               &  ! intent(in): runoff in future time steps (m s-1)
                ! output
                bvarData%var(iLookBVAR%averageInstantRunoff)%dat(1),           &  ! intent(out): instantaneous runoff (m s-1)
                bvarData%var(iLookBVAR%averageRoutedRunoff)%dat(1),            &  ! intent(out): routed runoff (m s-1)
                err,message)                                                                  ! intent(out): error control
 if(err/=0)then; err=20; message=trim(message)//trim(cmessage); return; endif
 end associate

 end subroutine run_oneGRU

end module run_oneGRU_module
