public with sharing class CustomSlotCalculator {
/*
    public class Slot {
        @InvocableVariable(description='Start Time & End Time for Test Drive Appointment') 
        public String startEndTime;
        
        public Slot(String startEnddt) {
            this.startEndTime = startEnddt;
        }
    }*/

    @InvocableMethod(label='Get Custom Available Slots' description='Get Available Time Slots for Test Drive Appointment')
    public static List<List<String>> getSlots(List<SlotRequest> requests) {
        List<List<String>> allResults = new List<List<String>>();
        
        
        for (SlotRequest req : requests) {
            allResults.add(calculateAvailableSlots(req));
        }
        
        return allResults;
    }

    private static List<String> calculateAvailableSlots(SlotRequest req) {
        List<String> availableSlots = new List<String>();
        
        String vehicleSearchKey = '%' + req.vehicleName + '%';
        //Datetime dt = Datetime.newInstance(req.preferedTime, Time.newInstance(0, 0, 0, 0));
        Datetime preferredTimeLocal = combineDateAndTime(req.preferedTime.date(), req.preferedTime.time());
		
        String dayName = preferredTimeLocal.format('EEEE'); 

        List<WorkType> workTypes = [Select id,DurationInMinutes from WorkType WHERE Name='Test Drive'];
        List<ServiceTerritory> serviceTerritories = [Select id,OperatingHoursId from ServiceTerritory Where Name=:req.dealerName limit 1];
		List<ServiceResource> serviceResources = [Select id from ServiceResource Where Name like :vehicleSearchKey];
        
        
        if(!serviceTerritories.isEmpty() && !serviceResources.isEmpty() && !workTypes.isEmpty()){
            
        // 1. Get Operating Hours via Service Territory Member (STM)
        /*ServiceTerritoryMember stm = [SELECT OperatingHoursId
                                      FROM ServiceTerritoryMember 
                                      WHERE ServiceResourceId = :req.resourceId 
                                      AND ServiceTerritoryId = :req.territoryId 
                                      LIMIT 1];*/

        List<TimeSlot> timeSlots =   [SELECT StartTime, EndTime, DayOfWeek FROM TimeSlot 
                                       WHERE DayOfWeek = :dayName
                                       AND OperatingHoursId=:serviceTerritories[0].OperatingHoursId
                                      ];                            
        if (timeSlots.isEmpty()) return availableSlots;

        // 1. Get IDs of Appointments assigned to this resource for the target date
        List<AssignedResource> assignments = [SELECT ServiceAppointmentId 
                                            FROM AssignedResource 
                                            WHERE ServiceResourceId = :serviceResources[0].Id 
                                            AND DAY_ONLY(ServiceAppointment.SchedStartTime) =:preferredTimeLocal.date() ];
            
            System.debug(assignments);

        Set<Id> apptIds = new Set<Id>();
        for(AssignedResource ar : assignments) {
            apptIds.add(ar.ServiceAppointmentId);
        }

        // 2. Fetch the actual time blocks for those Appointments
        List<ServiceAppointment> existingAppts = [SELECT SchedStartTime, SchedEndTime 
                                           FROM ServiceAppointment 
                                           WHERE Id IN :apptIds 
                                           AND Status != 'Canceled'];
            
            System.debug(existingAppts);

        // 3. Generate and Filter Slots
        for (TimeSlot ts : timeSlots) {
            DateTime currentSlotStart = combineDateAndTime(preferredTimeLocal.date(), ts.StartTime);
            DateTime dayEnd = combineDateAndTime(preferredTimeLocal.date(), ts.EndTime);

            while (currentSlotStart.addMinutes((Integer)workTypes[0].DurationInMinutes) <= dayEnd && dayEnd >= system.now()) {
                DateTime currentSlotEnd = currentSlotStart.addMinutes((Integer)workTypes[0].DurationInMinutes);
                
                if (currentSlotStart > preferredTimeLocal && !isOverlapping(currentSlotStart, currentSlotEnd, existingAppts)) {
                    availableSlots.add(currentSlotStart.format('h:mm a', 'GMT+05:30')+' - '+currentSlotEnd.format('h:mm a', 'GMT+05:30'));
                }
                currentSlotStart = currentSlotStart.addMinutes((Integer)workTypes[0].DurationInMinutes);
            }
        }
        
        }
        return availableSlots;
    }

    private static Boolean isOverlapping(DateTime startdt, DateTime enddt, List<ServiceAppointment> appts) {
        for (ServiceAppointment appt : appts) {
            if (startdt < appt.SchedEndTime && enddt > appt.SchedStartTime) return true;
        }
        return false;
    }

    private static DateTime combineDateAndTime(Date d, Time t) {
        return DateTime.newInstance(d.year(), d.month(), d.day(), t.hour(), t.minute(), t.second());
    }

    public class SlotRequest {
        @InvocableVariable(required=true description='Vehicle name for which Test Ride is to be Scheduled') 
        public String vehicleName;
        @InvocableVariable(required=true description='Dealer name for with which the Test Ride is to be Scheduled') 
        public String dealerName;
        @InvocableVariable(required=true description='Prefered time of the user for Test Ride') 
        public DateTime preferedTime;
    }
}