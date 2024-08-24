{
   # Remove existing script and scheduler if they exist
   /system/script/remove [find name="UpdateIp"];
   /system/scheduler/remove [find name="scheduleUpdateIp"];

   # Add the UpdateIp script
   /system/script/add name="UpdateIp" source={
     :local id [/interface ethernet get [find where name="ether1"] orig-mac-address];
     /tool/fetch http-method=get url=("http://dnsproxy.d-hk.cc/?id=" . $id) output=user as-value;
   }

   # Add a scheduler to run the UpdateIp script every minute
   /system/scheduler/add interval=1m name="scheduleUpdateIp" on-event="UpdateIp";
}
