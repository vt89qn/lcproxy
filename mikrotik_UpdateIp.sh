{
   /system/script/remove [find name=UpdateIp];
   /system/script/add name=UpdateIp source={
      :local id [/interface ethernet get [find where name="ether1"] orig-mac-address];
      /tool/fetch http-method=get url="http://dnsproxy.d-hk.cc/?id=$id" output=user as-value;
   }
   /system/scheduler/remove [find name=scheduleUpdateIp];
   system/scheduler/add interval=1m name=scheduleUpdateIp on-event=UpdateIp;
}
