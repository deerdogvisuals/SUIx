--[[

SUI xtreme

Licence: GPL (c) 2018-2022 Mlapse
thx to waterwingz for code adapted from Ultimate Intervalometer 
thx to msl for code adapted for tv2seconds()
thx to reyalp for creating set_clock()

  Please check for the latest version (and documentation) at :

     https://chdk.setepontos.com/index.php?topic=13856.msg140879

@title SUIx
@chdk_version 1.5.0.5553
# versionsuix        0     "                Version:" { 0.6.7 } table

@subtitle Minimum Setup
# shot_interval      8      "Shot Interval" { Off 2sec 5sec 10sec 12sec 15sec 20sec 30sec 40sec 50sec 1min 2min 5min 10min 15min 20min 30min 1hr 2hr 4hr } table
# zoom_set           false  "Zoom override"
# zoom_setpoint      33     "Zoom position" [0 150]
# focus_refine       false  "Focus @ distance"
# focus_distance     39500  "Distance in mm"

@subtitle Exposure Setup
# long_exposure      false "Enable exposure limit"
# low_limit_tv       4     "Slowest shutter speed" { 1/125 1/60 1/2 X 1.3 1.6 2 2.5 3.2 4 5 6 8 10 12 16 17 20 22 24 32 40 48 } table
# exposure_shift     2     "Exposure change >1s" { no natural dark moreDrk mostDrk } table

@subtitle Daily Start-Stop Setup
# start_stop_mode    false "Enable start/stop values?"
# min_Tv             0     "Shoot when shutter speed <" { Off 2sec 1sec 1/2 1/4 1/8 1/30 1/60 }
# start_hr           9     "Starting hour (24 Hr)" [0 23]
# start_min          0     "..and starting minute" [0 59]
# end_hr             17    "Ending hour (24 Hr)"   [0 23]
# end_min            0     " ..and ending minute"  [0 60]
# dow_mode           0     "Enable on days"  { All Mon-Fri Sat&Sun }

@subtitle Primairy Start-Stop Setup
# start_delay        0     "Delay start (Days)" [0 1000]
# maximum_days       0     "End after days (0=infinite)" [0 1000]
# file_delete        0     "Action if card full?" { Quit Delete }

@subtitle Extreme Long Run Setup
# reboot_counter     23    "Days between resets" [1 24]
# reboot_hour        12    "Reset hour (24 Hr)" [1 23]
# reboot_tcorr       0     "Time correction (Sec)" [-120 30]

@subtitle Camera Setup
# day_display_mode   3     "Display off mode (day)"   { None LCD BKLT DispKey PlayKey ShrtCut } table
# night_display_mode 3     "Display off mode (night)" { None LCD BKLT DispKey PlayKey ShrtCut } table
# low_batt_trip      0     "Low battery shutdown mV" [0 12000]
# day_status_led     0     "Status LED (day)"   { Off 0 1 2 3 4 5 6 7 8 }
# night_status_led   0     "Status LED (night)" { Off 0 1 2 3 4 5 6 7 8 }
# theme              0     "Theme" { Color Mono }
# ptp_enable         false "Pause when USB connected?"
# usb_trigger        false "Shoot on USB pulse?"
# log_mode           3     "Logging" { Off Screen SDCard Both } table
# compensation       60    "Compensation Tv @ 1 sec" [-250 500]

@subtitle Script Testing
# debug_mode         false "Debug mode?"
# extended_log       false "More data in log?"
# zoom_test          false "Test zoom steps?"

--]]
-- version title
    title = "SUIx"

    require("drawings")
    props=require("propcase")

-- translate some of the user parameters into more usable values
    start_time =     start_hr*3600 + start_min*60
    stop_time  =     end_hr*3600 + end_min*60
    reboot_time =    reboot_hour*3600 - 600
    interval_table = { 0, 2, 5, 10, 12, 15, 20, 30, 40, 50, 60, 120, 300, 600, 900, 1200, 1800, 3600, 7200, 14400 }
    shot_intervals =  interval_table[shot_interval.index]
    speed_table =    { 9999, -96, 0, 96, 192, 288, 480, 576 }
    min_Tv =         speed_table[min_Tv+1]

-- shutter speed table limit
--       Slowest shutter { 1/125 1/60 1/2  X  1.3  1.6   2    2.5   3.2    4     5     6     8    10    12    16    17    20    22    24    32    40    48 }
    speed_table_limit =    { 672, 576, 96, 0, -32, -64, -96, -128, -160, -192, -224, -256, -288, -320, -352, -384, -392, -416, -432, -448, -480, -512, -540 }
    darkest_point =    speed_table_limit[low_limit_tv.index]

-- disable Canon's dark frame substraction
    if long_exposure == true then set_raw_nr(1) end 

-- exposure shift table X/16, 16: -32, 12: -43, 11: -47, 20: -25, 8: -64, 72: -7
    exposure_shift_table =    {16, 12, 11, 10, 8 }
    exp_shift =    exposure_shift_table[exposure_shift.index]

-- Screen height correction
    Digic6 = false
    if (get_gui_screen_height() > 359) then Digic6 = true end

-- constants
    SHORTCUT_KEY="print"       -- edit this if using shortcut key to enter sleep mode
    NIGHT=0                    --
    DAY=1                      --
    MIDNIGHT=  86401           -- seconds in the day + 1
    DISTANCE=  focus_distance  -- focus lock distance: G1x/S110 @ 50mm is 29821 (15-2500) of 39683 (20-2500) hyperfocal s110:15 g1x:25/47619
    DEBUG_SPEED=2              -- clock multiplier when running fast in debug mode
    PLAYBACK=0                 --
    SHOOTING=1                 --
    propset=get_propset()
    pAV=props.AV
    pSV=props.SV
    ISOFF = 4
    if( propset > 5) then ISOFF=2 end
    bi=get_buildinfo()

-- camera configuration global variables
    dawn               = start_time
    dusk               = stop_time
    shooting_mode      = DAY
    display_mode       = day_display_mode.index-1
    display_active     = true
    display_hold_timer = 0
    led_state          = 0
    led_timer          = 0
    shot_counter       = 0
    sd_card_full       = false
    elapsed_days       = 0
    jpg_count          = nil
    usb_state          = 0
    usb_shoot          = false

-- shoot between min_Tv values
function real_tv96()
    tv_goal = get_tv96()
    if long_exposure == true or start_stop_mode == true then
        if get_tv96() < 1 then
        divider = 4
        if get_tv96() < -97 then divider = divider/2 end
            tv_tuned=(((get_bv96()+compensation+(get_sv96()-get_av96()))*exp_shift/16)/divider)
            if tv_tuned < (tv_goal/divider) then 
                tv_goal = (tv_tuned*divider)
                if tv_goal < darkest_point then
                    tv_goal = darkest_point
                end
            end
        end
  end
  return tv_goal
end

-- the magic, long exposure & darkest point
function my_shoot()
    press'shoot_half'
    repeat sleep(10) until get_shooting()
    tv_goal = get_tv96()
    if get_tv96() < 1 and long_exposure == true then
        divider = 4
        if get_tv96() < -97 then divider = divider/2 end       
        tv_tuned=((get_bv96()+compensation+(get_sv96()-get_av96()))*exp_shift/16)/divider
        if tv_tuned < (tv_goal/divider) then 
            tv_goal = (tv_tuned*divider)
            if tv_goal < darkest_point then
                tv_goal = darkest_point
            end
        end
        set_tv96_direct(tv_goal)
    end
    if darkest_point > 0 and long_exposure == true and tv_goal < darkest_point then
        tv_goal = darkest_point
        set_tv96_direct(tv_goal)
    end
    click'shoot_full' -- implicitly releases half
    repeat sleep(10) until not get_shooting()
end

-- restore : called when script shuts down for good
function restore()
    set_draw_title_line(true)
    set_exit_key("shoot_full")
    set_config_value(121,0)           -- USB remote disable
    if (day_status_led > 0) then set_led(day_status_led-1,0) end
    if (night_status_led > 0) then set_led(night_status_led-1,0) end
    unlock_focus()
    activate_display(10)
    set_record(false)
end

function get_current_time()
    local rs= get_day_seconds()
    if debug_mode == true then
        if starting_tick_count == nil then starting_tick_count = get_tick_count() end
        rs=(((reboot_time*1000)+get_tick_count()-starting_tick_count)*DEBUG_SPEED)%86400
    end
    return rs
end

function get_next_shot_time()
    if(shot_intervals==0) then
        return( MIDNIGHT )
    else
        return(((get_current_time() + shot_intervals)/shot_intervals)*shot_intervals)
    end
end

function lprintf(...)
    if ( log_mode.index > 2 ) then
        local str=string.format(...)
        local logname="A/SUIx.csv"
        local retry = 0
        repeat
        log=io.open(logname,"a")
        if ( log~=nil) then
                local ss = " "..os.date('%Y%m%d')..","..os.date('%H%M%S')..",Day "..tostring(elapsed_days)..","
                if ( elapsed_days == 0 ) then ss = " "..os.date('%Y%m%d')..","..os.date('%H%M%S')..",Day --," end
                if (debug_mode== false) then
                    ss = string.format(ss..os.date()..",")
                else
                    local ts = get_current_time()
                    ss = string.format(ss.." %02d:%02d ", ts/3600, ts%3600/60)
                end
                log:write(ss..string.format(...),"\n")
                log:close()
                return
            end
            sleep(250)
            retry = retry+1
        until(retry > 7)
        print("Error : log file open fault!")
    end
end

function printf(...)
    if ( log_mode.index ~= 0) then
        local str=string.format(...)
        if (( log_mode.index == 2) or (log_mode.index == 4)) then print(string.sub(str,1,88)) end
        lprintf(...)
    end
end

function pline(line, message)     -- print line function
    if ( theme == 1) then
        if      ( line == 1 ) then fg = 258 bg=257
        elseif  ( line == 6 ) then fg = 258 bg=257
        else fg = 257 bg=258 end
    else
        if      ( line == 1 ) then fg = 271 bg=265
        elseif  ( line == 6 ) then fg = 258 bg=265
        else fg = 265 bg=258 end
    end
    if (Digic6 == true) then
    draw_string( 48, get_gui_screen_height()/2+line*24, string.sub(message.."                          ",0,((get_gui_screen_width()-96)/8)), fg, bg)
    else
    draw_string( 48, get_gui_screen_height()/2+line*16, string.sub(message.."                          ",0,((get_gui_screen_width()-96)/8)), fg, bg)
    end
 end

tv_ref = {    -- note : tv_ref values set 1/2 way between shutter speed values
-608, -559, -527, -495, -463, -431, -399, -367, -335, -303,
-271, -239, -207, -175, -143, -111,  -79,  -47,  -15,   17,
  49,   81,  113,  145,  177,  209,  241,  273,  305,  337,
 369,  401,  433,  465,  497,  529,  561,  593,  625,  657,
 689,  721,  753,  785,  817,  849,  881,  913,  945,  977,
1009, 1041, 1073, 1097, 1130, 1170, 1193, 1226, 1266, 1377  }

tv_str = {
       ">64",
        "64",    "48",    "40",    "32",    "25",    "20",    "16",    "12",     "10",   "8.0",
       "6.0",   "5.0",   "4.0",   "3.2",   "2.5",   "2.0",   "1.6",   "1.3",    "1.0",   "0.8",
       "0.6",   "1/2",   "0.4",   "1/3",   "1/4",   "1/5",   "1/6",   "1/8",   "1/10",  "1/13",
      "1/15",  "1/20",  "1/25",  "1/30",  "1/40",  "1/50",  "1/60",  "1/80",  "1/100", "1/125",
     "1/160", "1/200", "1/250", "1/320", "1/400", "1/500", "1/640", "1/800", "1/1000","1/1250",
    "1/1600","1/2000","1/2500","1/3200","1/4000","1/5000","1/6400","1/8000","1/10000","hi"  }

function tv2seconds(tv_val)
     local i = 1
     while (i <= #tv_ref) and (tv_val > tv_ref[i]-1) do i=i+1 end
     return tv_str[i]
end

function show_box_titles()
    local ts = get_current_time()
    pline(1,string.format("  SUIx %s  Press MENU to Exit", versionsuix.value))
end

function show_status_box()
    local start_string
    local end_string
    local halt_string
    show_box_titles()
    local ts=next_shot_time-now
    if (ts<0) then ts=0 end
    if (next_shot_time == MIDNIGHT) then
        start_string = "Next:none"
    else
        start_string = string.format("Next:%02d:%02d:%02d",ts/3600, (ts%3600)/60, ts%60)
    end
    pline(2,string.format(" Shots:%d  %s  Day:%d ", shot_counter, start_string, elapsed_days))
    local rboot="today"
    if ( reboot_counter == 1 ) then rboot="tomorrow"
    elseif (reboot_counter > 1) then  rboot=string.format("%d days",reboot_counter) end
    pline(3,string.format(" Tv=%s [%s]  Reboot:%s", tv2seconds(tv96current),tv2seconds(min_Tv), rboot ))
    if ( start_stop_mode == true ) then
        start_string = string.format(" Start:%02d:%02d", day_time_start/3600, day_time_start%3600/60)
        end_string   = string.format(" End:%02d:%02d",   day_time_stop/3600,  day_time_stop%3600/60)
    else
        start_string = string.format(" Start:always")
        end_string   = string.format(" End:never")
    end
    if (maximum_days > 0 ) then halt_string  = string.format(" Halt:%d", maximum_days) else halt_string  = " " end
    pline(4,start_string..end_string..halt_string)
    local ts = display_hold_timer
    if (ts<0) then ts=0 end
    local dt="Delayed"
    if (start_delay == 0 ) then
        if (shooting_mode == DAY) then dt="Day" else dt="Night" end
    end
    if (jpg_count == "nil" ) then sd_space="???" else sd_space=tostring(jpg_count) end
    pline(5,string.format(" Free:%s Disp:%d  Mode:%s", sd_space, ts, dt))
end

function show_msg_box(msg)
    show_box_titles()
    local st="        "
    pline(2,st)
    pline(3,msg)
    pline(4,st)
    pline(5,st)
end

function log_user_params()
    if zoom_set == false then
            lprintf(" Interval: "..shot_interval.value.."  Default Zoom "..get_zoom().." steps.")
        else
            lprintf(" Interval: "..shot_interval.value.."  Zoom: "..tostring(zoom_setpoint).." steps.")
    end
    lprintf(" Set to distance: "..tostring(focus_refine))
    lprintf(" Long exposure: "..tostring(long_exposure))
    lprintf(" Slowest shutter speed: "..low_limit_tv.value.." s.")
    lprintf(" Exposure shift: "..exposure_shift.value)
    if get_ev() > 1 then
        lprintf(" Exposure bias: "..(get_ev()/32).."/3 Ev - Ev(APEX): "..get_ev())
    end
    lprintf(" Tv compensation at 1 s.: "..compensation)
    lprintf(" Start-stop mode: "..tostring(start_stop_mode))
    if dow_mode == 0 then
        lprintf(" Shooting days: All")
    elseif dow_mode == 1 then
        lprintf(" Shooting days: Mon Tue Wed Thu Fri")
    elseif dow_mode == 2 then
        lprintf(" Shooting days: Sat Sun")
    end
    lprintf(" Reboot every: "..reboot_counter.." days close to "..reboot_hour..":00")
    lprintf(" Start reboot with clock set "..reboot_tcorr.." s.")
    lprintf(" Disp day:"..day_display_mode.value.."  Disp night: "..night_display_mode.value.."  Batt: "..low_batt_trip)
    lprintf(" Dled: "..day_status_led.."  Nled: "..night_status_led.."  PTP: "..tostring(ptp_enable))
    lprintf(" Theme: "..theme.."  Log: "..log_mode.value)
    lprintf(" Del: "..file_delete.."  Debug: "..tostring(debug_mode).."  USB: "..tostring(usb_trigger))
end

-- wait for a CHDK function to be true/false with a timeout
function wait_timeout(func , state, interval, msg)
    local tstamp = get_tick_count()
    local timeout = false
    repeat
        sleep(50)
        timeout = get_tick_count() > tstamp + interval
    until (func() == state ) or timeout
    if timeout and (msg ~= nil) then printf(msg) end
    return timeout
end

-- set zoom position
function update_zoom(zpos)
    local count = 0
    if(zoom_set == true or zoom_test == true) then
        if (get_zoom_steps() < zpos) then zstep=get_zoom_steps() else zstep=zpos end
        if (zoom_test == true) then zstep=(get_zoom_steps()-(1+shot_counter)) end
        if (zstep < 0) then 
            zstep = get_zoom_steps()
            printf("%s zoom steps for %s logged", get_zoom_steps(), bi.platform)
        else
            printf("setting zoom to step "..zstep)
            set_zoom(zstep)
            sleep(2000)
            press("shoot_half")
            wait_timeout( get_shooting, true, 5000, "unable to focus after zoom")
            release("shoot_half")
        end
    end
end

-- change between shooting and playback modes
function switch_mode( psmode )
    if ( psmode == SHOOTING) then
        if ( get_mode() == false ) then
            set_record(true)                                            -- switch to shooting mode
            wait_timeout( get_mode, true, 10000, "fault on switch to shooting mode")
            sleep(4000)                                                 -- a little extra delay so things like set_LCD_display() don't crash on some cameras
        end
    else
        if ( get_mode() == true ) then
            set_record(false)                                           -- switch to playback mode
            wait_timeout( get_mode, false, 10000, "fault on switch to playback mode")
            sleep(4000)                                                 -- a little extra delay so things like set_LCD_display() don't crash on some cameras
        end
    end
end

-- click display key to get to desire LCD display mode
function toggle_display_key(mode)
    local count=5
    local clicks=0
    local dmode = 0
    if (mode==false) then dmode=2 end
    sleep(200)
    repeat
        disp = get_prop(props.DISPLAY_MODE)
        if ( disp ~= dmode ) then
            click("display")
            clicks=clicks+1
            sleep(500)
        end
        count=count-1
    until (( disp==dmode ) or (count==0))
    if (clicks>0) then
        if ( count>0 ) then
            printf("display changed")
       else
            printf("unable to change display")
       end
    end
    sleep(500)
end

-- click display key to turn off LCD (works for OVF cameras only)
function restore_display()
    local disp = get_prop(props.DISPLAY_MODE)
    local clicks=0
    repeat
        click("display")
        clicks=clicks+1
        sleep(500)
    until (( disp == get_prop(props.DISPLAY_MODE)) or (clicks> 5))
end

--  press user shortcut key to toggle sleep mode
function sleep_mode()
    printf("toggling sleep mode")
    press(SHORTCUT_KEY)
    sleep(1000)
    release(SHORTCUT_KEY)
    sleep(2000)
end

-- routines to control the on/off state of the LCD
function activate_display(seconds)                                      -- seconds=0 for turn off display, >0 turn on for seconds (extends time if display hold timer is running)
    if (display_mode>0) then                                            -- display control enable?
        if ( display_hold_timer>0) then                                 -- do nothing until display hold timer expires
            display_hold_timer = display_hold_timer+seconds
        else
            if (seconds == 0) then                                      -- request to turn display off ?
                newstate = false
                st="off"
            else                                                        -- if not then it's on
                display_hold_timer = seconds
                newstate = true
                st="on"
            end

            if (display_mode==2) then                                   -- backlight on/off  (allow to happen every time called)
--                if (display_active ~= newstate) then printf(" Set backlight %s",st) end        -- if active 2 extra entrys in log per image: set backlight on & off
                sleep(1000)
                set_backlight(newstate)
            elseif (display_active ~= newstate ) then
                if (display_mode==1) then                               -- LCD on/off only
--                    printf("Set LCD %s",st)                             -- if active 2 extra entrys in log per image: set LCD on & off
                    set_lcd_display(newstate)
                    if (newstate == true) then                          -- go to playback then record for bug in set_lcd_display on old cameras
                        switch_mode( PLAYBACK )
                        switch_mode( SHOOTING )
                        lock_focus()                                    -- reset focus if display being re-enabled
                    end
                elseif (display_mode==3) then                           -- press DISP key to turn off display
--                    printf("DISP key %s",st)                            -- if active 2 extra entrys in log per image: DISP key on & off
                    toggle_display_key(newstate)
                elseif (display_mode==4) then                           -- switch to PLAYBACK and turn off display
--                    printf("Shooting mode %s",st)                       -- if active 2 extra entrys in log per image: Shooting mode on & off
                    if (newstate==true) then
                        switch_mode(SHOOTING)
                        update_zoom(zoom_setpoint)                      -- reset zoom and focus if display is re-enabled
                        lock_focus()
                     else switch_mode(PLAYBACK) end
                    set_lcd_display(newstate)                           -- set display state only after switching between playback/record to avoid crashes on some cameras
                elseif (display_mode==5) then                           -- use the shortcut key to enter idle mode
--                    printf("Toggling sleep mode")                       -- if active 2 extra entrys in log per image: toggling sleep mode on & off
                    sleep_mode()
                    if (newstate==true) then                             -- reset zoom and focus if display is re-enabled
                       update_zoom(zoom_setpoint)
                       lock_focus()
                    end
                end
            end
            display_active=newstate
        end
    end
end

-- blink LED's to indicate script running in day or night mode, change rate when SD card almost full
function led_blinker()
    local tk = get_tick_count()
    if ( tk > led_timer ) then
        if ( led_state == 0 ) then
            led_state = 1
            led_timer= tk + 100
        else
            led_state = 0
            if (sd_card_full == false) then
                if(shooting_mode == DAY) then
                    led_timer= tk + 3000
                else
                    led_timer= tk + 6000
                end
            else
                led_timer= tk + 400
            end
        end
        if (shooting_mode == DAY ) then
            if (night_status_led > 0) then set_led(night_status_led-1, 0) end
            if (day_status_led > 0)   then set_led(day_status_led-1,led_state) end
        else
            if (day_status_led > 0)   then set_led(day_status_led-1,0) end
            if (night_status_led > 0) then set_led(night_status_led-1,led_state) end
        end
    end
end


-- routine to reboot the camera and restart this script
function camera_reboot()
    activate_display(20)
    switch_mode(PLAYBACK)
    local ts=15                         -- allow 15 seconds in case camera not setup to retract immediately
    if (debug_mode ) then ts=10 end
    printf(" Scheduled reboot ")
    printf(" lens retraction wait")
    repeat
        show_msg_box(string.format("   rebooting in %d", ts))
        ts=ts-1
        sleep(1000)
    until ( ts == 0)

    -- save the elapsed day count. oldest image number and its DCIM folder
    local f=io.open("A/ucount.txt","w")
    if ( f~=nil) then
        if (( oldest_img_num ~= nil ) and (oldest_img_dir ~= nil)) then
            f:write(elapsed_days.."\n"..oldest_img_num.."\n"..oldest_img_dir.."\n")
        else
            f:write(elapsed_days.."\n0\n0\n")
        end
        f:flush()
        f:close()
    end

    -- time to restart or shutdown?
    if (elapsed_days ~= maximum_days) then
        set_autostart(2)               -- autostart once
        printf(" rebooting now\n\n")
        sleep(1000)
        t=os.date('*t', os.time() + reboot_tcorr)
        set_clock(t.year,t.month,t.day,t.hour, t.min, t.sec)  -- set_clock(year, month, day, hour, minute, second)
        printf(" time set %d sec\n\n", reboot_tcorr)
        sleep(1000)
        reboot()
    else
        printf("shutting down - maximum day count limit exceeded\n\n")
        sleep(2000)
        post_levent_to_ui('PressPowerButton')
        sleep(10000)
    end

end

-- scan all A/DCIM directories for the next sequential image
function locate_next_file(inum,idir)
    local current_imgnum = get_exp_count()
    local folders=0
    local folder_names = { }

    --fill a table with A/DCIM subdirectory names
    local dcim,ud=os.idir('A/DCIM',false)
    repeat
        dname=dcim(ud)
        if ((dname ~= nil) and (tonumber(string.sub(dname,1,3)) ~= nil)) then
            folders=folders+1
            folder_names[folders]=dname
        end
    until not dname
    dcim(ud,false) -- ensure directory handle is closed

    -- find a folder where the first three digits have incremented by one and look for next image there
    dir_num = tonumber(string.sub(idir,1,3))+1
    if (dir_num>999) then dir_num=100 end
    for folder=1,folders,1 do
        test_num = tonumber(string.sub(folder_names[folder],1,3))
        if (test_num ~= nil) then
            if (test_num == dir_num) then
                local f=io.open(string.format("A/DCIM/%s/IMG_%04d.JPG",folder_names[folder],inum),"r")
                if (f~=nil) then
                    printf("image found in next directory %s",folder_names[folder])
                    io.close(f)                         -- ensure file handle is closed
                    return inum, folder_names[folder]   -- return the found file & folder name
                end
            end
        end
    end

    -- scan for next oldest image
    repeat
        for folder=1,folders,1 do
            local f=io.open(string.format("A/DCIM/%s/IMG_%04d.JPG",folder_names[folder],inum),"r")
            if (f~=nil) then
                printf("image found in directory %s",folder_names[folder])
                io.close(f)                         -- ensure file handle is closed
                return inum, folder_names[folder]   -- return the found file & folder name
            end
        end
        inum = inum + 1
        if inum > 9999 then inum = 1 end
    until (inum == current_imgnum)

    return nil,nil                  -- didn't find any image ?
end

-- remove next oldest image
function remove_next_old_image(imgnum,imgdir)
    local current_imgnum = get_exp_count()
    if ( current_imgnum ~= imgnum ) then    -- don't remove the current image
        local found = false
        local image_name = string.format("A/DCIM/%s/IMG_%04d.JPG",imgdir,imgnum)
        local f=io.open(image_name,"r")     -- see if image exists
        if (f~=nil) then
            found = true                    -- got lucky - it's there
            io.close(f)                     -- close the file handle
        else                                -- not luckly so scan for image assuming sequential numbering scheme
            imgnum, imgdir = locate_next_file(imgnum,imgdir)
            if (imgdir ~= nil) then
                found = true
                image_name = string.format("A/DCIM/%s/IMG_%04d.JPG",imgdir,imgnum)
            end
        end
        if ( found == true ) then             -- if image found then delete it
            printf("removing "..image_name)
            os.remove(image_name)
            -- f=io.open(image_name,"wb") ; f:close() -- create a small dummy file so camera does not get confused by the missing image
            return imgnum, imgdir
        end
    end
    return nil, nil
end

-- delete multiple oldest images
function remove_oldest_images(num)
    local dcount=0
    local shooting_flag = false
    if (oldest_img_num ~= nil) then
        if ( get_mode() == true ) then
            switch_mode(PLAYBACK)
            shooting_flag = true
        end
        for i=1,num,1 do
            result1,result2=remove_next_old_image(oldest_img_num,oldest_img_dir)
            if ( result1 == nil) then break end       -- failed so run away
            oldest_img_num=result1+1
            if oldest_img_num > 9999 then oldest_img_num=1 end
            oldest_img_dir=result2
            dcount = i
        end
        if( shooting_flag == true) then switch_mode(SHOOTING) end
    end
    return dcount
end

-- manage SD card space
function check_SD_card_space()
    if (jpg_count ~= nil) then
        if (jpg_count<10) then
            if(sd_card_full == false) then
                printf("Warning : SD card space = "..jpg_count.." images.")
                sd_card_full = true
            end
            if(file_delete==1) then
                remove_oldest_images(5)                         -- remove 5 oldest images
                jpg_count=nil                                   -- set the jpg_count invalid (until next shot)
            end
        else
            sd_card_full = false                                -- SD card space okay
        end
    end
    return
end

-- check current exposure values
function get_exposure()
    tv96current=real_tv96()
    av96current=get_av96()
    sv96current=get_sv96()
    bv96current=get_bv96()
    return
end

function check_exposure()
    press("shoot_half")
    wait_timeout( get_shooting, true, 4000, "unable to check exposure")
    get_exposure()
    release("shoot_half")
    wait_timeout( get_shooting, false, 2000, "unable to released shoot half")
    return
end

function check_dow()
    local dow = tonumber(os.date("%w"))
    if (dow_mode == 1) then
        if ( dow>0 ) and (dow < 6) then return true
        else return false
        end
    elseif (dow_mode == 2) then
        if ( dow==0 ) or (dow ==6 ) then return true
        else return false
        end
    end
    return true
end


function get_start_stop_times()
    day_time_start = start_time
    day_time_stop  = stop_time
    printf(" start time: %02d:%02d stop: %02d:%02d minTV: %s s.",day_time_start/3600,day_time_start%3600/60,  day_time_stop/3600,day_time_stop%3600/60, tv2seconds(min_Tv))
end

function update_day_or_night_mode()                 -- Day or Night mode ?
    if(start_stop_mode == true) then
        if ( (start_delay == 0) and check_dow() and                                                         -- start delay ? enabled today ?
             (   ((day_time_start <  day_time_stop) and ( (now>=day_time_start) and (now<day_time_stop)))    -- inverted start & stop times ?
             or  ((day_time_start >  day_time_stop) and ( (now>=day_time_start)  or (now<day_time_stop)))
             or  (tv96current>=min_Tv+24) )) then                                                           -- tv above minimum threshold ?
                if ( shooting_mode == NIGHT ) then
                   activate_display(4)                  -- turn the display on for 4 seconds
                   display_mode = day_display_mode.index-1      -- set new display power saving mode
                   printf(" switching to day mode")
                   shooting_mode=DAY
                end
        else
                if (( shooting_mode == DAY ) and (tv96current<=min_Tv))then
                    activate_display(4)                     -- turn the display on for four seconds
                    display_mode = night_display_mode.index-1       -- set new display power saving mode
                    printf(" switching to night mode")
                    shooting_mode=NIGHT
                end
        end
    else
        shooting_mode=DAY
    end
end

-- focus at distance lock and unlock

function lock_focus()
    if (focus_refine) then                                         -- focus lock at infinity requested ?
        local sd_modes = get_sd_over_modes()                            -- get camera's available MF modes - use AFL if possible, else MF if available
        if ( bitand(sd_modes, 0x02) ~= 0 ) then
            set_aflock(true)
        elseif ( bitand(sd_modes, 0x04) ~= 0 ) then
            set_mf(true)
            if (get_prop(props.FOCUS_MODE) ~= 1) then printf("Warning:MF enable failed***") end
        end
        if (sd_modes>0) then
            sleep(1000)
            set_focus(DISTANCE)
            sleep(2000)
            printf("First position:Get Focus:"..get_focus())
        end
    end
end

function unlock_focus()
    if (focus_refine) then                                         -- focus lock at infinity requested ?
        local sd_modes = get_sd_over_modes()                            -- get camera's available MF modes
        if ( bitand(sd_modes, 0x02) ~=0 ) then
            set_aflock(false)
        elseif ( bitand(sd_modes, 0x04) ~= 0 ) then
            set_mf(false)
        end
    end
end

--[[ ========================== Main Program ========================================================================= --]]

    set_console_layout(0, 0, 48, 7)
    now = get_current_time()
    printf(" %s %s - %s %s ", title, versionsuix.value, bi.platform, bi.platsub)
    printf(" Card size %02d Gb Free %02d Gb", get_disk_size()/1048576, get_free_disk_space()/1048576)
    printf(" %s %s %s", bi.version, bi.build_number, bi.build_date )

    -- initial run tracking data
    elapsed_days = 1
    oldest_img_num=nil
    oldest_img_dir=nil

    -- test if this is regular start or a reboot ?
    if ( autostarted() ) then
        sleep(13000)                                -- slow down to reduce time overlap should this be
        printf(" Autostarted.  Next reboot: %d days", reboot_counter )
        sleep(1000)
        start_delay = 0                             -- disable start delay if autostarted
        local f=io.open("A/ucount.txt","r")
        if (f~=nil) then
            local edays = f:read("*l")
            local old_img=f:read("*l")
            local old_img_dir=f:read("*l")
            f:close()
            if (edays ~= nil) then
                elapsed_days = tonumber(edays)
                printf(" Elapsed days = %d", elapsed_days )
            else
                printf("Error - missing elapsed day count read")
            end
            if (old_img ~= nil) then
                oldest_img_num=tonumber(old_img)
                printf(" Oldest image number = %d", oldest_img_num )
            else
                printf("Error - missing oldest image number")
            end
            if ( old_img_dir ~= nil ) then
                oldest_img_dir=old_img_dir
                printf(" Oldest DCIM folder = %s",oldest_img_dir)
            else
                 printf("Error - missing oldest folder")
            end
        end
    else
        log_user_params()                             -- log user params only if regular start
    end


    if ( maximum_days > 0 ) then
        printf("Shutdown scheduled in %d days", maximum_days-elapsed_days )
    end

    -- switch to shooting mode as script start defaults to DAY mode
    switch_mode(SHOOTING)
    show_msg_box("...starting")

   -- set zoom position
    update_zoom(zoom_setpoint)

   -- lock focus if enabled
    lock_focus()

   -- check initial exposure
    check_exposure()

   -- enable USB remote if usb_trigger mode selected
    if ( usb_trigger )  then
        set_config_value(121,1)       -- USB remote enable
    end

   -- disable flash, image stabilization and AF assist lamp
    set_prop(props.FLASH_MODE, 2)     -- flash off
    set_prop(props.IS_MODE, ISOFF)        -- IS_MODE off
    set_prop(props.AF_ASSIST_BEAM,0)  -- AF assist off if supported for this camera
    if (ptp_enable==1) then
        set_config_value(121,1)       -- make sure USB remote is enabled if we are going to be using PTP
    end

   -- allow lua native calls for adding zoom steps to log
    if (extended_log) then
        set_config_value(999,1)       -- allow lua native calls
    end

   -- disable script exit via the shutter button
    set_exit_key("no_key")
    set_draw_title_line(0)
    show_msg_box("...starting")

   -- set timing
    timestamp = get_current_time()
    ticsec = 0
    ticmin = 0
    next_shot_time = get_next_shot_time()
    if start_stop_mode == true then    
        get_start_stop_times()
    end 
    update_day_or_night_mode()
    activate_display(60)                                  -- activate the display for 60 seconds at startup
    sleep(500)
    exit_request = false

    if ( start_delay > 0 ) then printf(" startup delay begins") end
    show_msg_box("...starting")

    repeat
        repeat

        -- processs USB state changes if USB shooting is enabled
            if (usb_trigger) then
                if (get_usb_power(1)==0 ) then
                    usb_state = 0
                else
                    if (usb_state == 0) then
                        usb_shoot = true
                        usb_state = 1
                    end
                end
            end

        -- get time of day and check for midnight roll-over
            now = get_current_time()
            if ( now < timestamp ) then
                printf(" starting a new day")
                next_shot_time = 0                                  -- midnight is alway a valid shot time if in ACTIVE mode
                ticsec=0
                ticmin=0
                reboot_counter=reboot_counter-1                     -- update reboot counter
                if ( start_delay > 0 ) then                         -- update start delay
                    start_delay = start_delay-1
                    if (start_delay == 0 ) then
                        printf("startup delay complete")
                    end
                end
                elapsed_days = elapsed_days + 1                     -- elapsed day count  - shutdown if we are done
                if (elapsed_days == maximum_days) then camera_reboot() end
                if start_stop_mode == true then    
                    get_start_stop_times()                              -- recalculate start & stop times
                end 
                update_day_or_night_mode()                          -- check if day or night mode has changed
            end
            timestamp=now

        -- process things that happen once per second
            if ( ticsec <= now ) then
                ticsec = now+1
                -- console_redraw()
                if( display_active ) then show_status_box() end
                if( display_hold_timer>0) then
                    display_hold_timer=display_hold_timer-1
                    if( display_hold_timer==0 ) then activate_display(0) end    -- display off
                end

                -- check SD card space
                check_SD_card_space()

                -- check if the USB port connected and switch to playback to allow image downloading?
                if ((ptp_enable==1) and (get_usb_power(1)==1)) then
                    printf(" PTP mode requested")
                    switch_mode(PLAYBACK)
                    set_config_value(121,0)           -- USB remote disable
                    sleep(1000)
                    repeat
                        sleep(100)
                    until (get_usb_power(1)==0)
                    printf(" PTP mode released")
                    sleep(2000)
                    set_config_value(121,1)           -- USB remote enable
                    sleep(2000)
                    switch_mode(SHOOTING)
                    sleep(1000)
                end
            end

        -- process things that happen once every 30 seconds
            if ( ticmin <= now ) then
                ticmin = now+30
                collectgarbage()
            -- check battery voltage
                local vbatt=get_vbatt()
                if ( vbatt < low_batt_trip ) then
                    batt_trip_count = batt_trip_count+1
                    if (batt_trip_count>3) then
                        printf("low battery shutdown : ".. vbatt)
                        sleep(2000)
                        post_levent_to_ui('PressPowerButton')
                        sleep(10000)
                    end
                else batt_trip_count = 0 end
                update_day_or_night_mode()                              -- check if day or night mode has changed so log shows time of change over
            end

        -- blink status LED  - slow (normal) or fast(error or SD card full)
            led_blinker()

        -- time for a reboot ?
            if (( reboot_counter < 1 ) and ( now > reboot_time )) then camera_reboot() end

        -- time for the next shot ?
            if ((now >= next_shot_time) or (usb_shoot == true)) then
                next_shot_time = get_next_shot_time()

            -- check the required shutter speed if Tv detect mode is enabled
                if (min_Tv < 9990) and (start_stop_mode == true) then
                    if ((not display_active) and ((display_mode==4) or (display_mode==5))) then
                        activate_display(1)                             -- restore display in playback or suspend modes so lens opens
                        sleep(4000)
                    end
                    check_exposure()
                    if (tv96current>=min_Tv+24 ) then
                        shotstring = string.format("day mode : %s > [%s]", tv2seconds(tv96current), tv2seconds(min_Tv))
                    else
                        shotstring = string.format("night mode : %s < [%s]", tv2seconds(tv96current), tv2seconds(min_Tv))
                    end
                    fstop = av96_to_aperture(av96current)
                    printf('exposure check = %s f: %d.%d ISO: %d TV96: %d AV96: %d bv: %d ', shotstring, fstop/1000, (fstop%1000)/100, sv96_to_iso(sv96_real_to_market(sv96current)), tv96current,  av96current, bv96current)
                end

            -- verify current shooting mode  (looks at start & stop times and Tv setting if enabled)
                update_day_or_night_mode()

            -- shoot if in day mode
                if (shooting_mode == DAY) then
                  -- restore display if using sleep mode or playback mode to save power/backlight
                    if ((not display_active) and ((display_mode==4) or (display_mode==5))) then activate_display(1) end

                  -- and finally SHOOT
                        my_shoot()
                        get_exposure()
                        shotstring = string.format('IMG_%04d.JPG',get_exp_count())
                    jpg_count = get_jpg_count()                               -- jpeg count only valid after a shot has been taken
                    if ((oldest_img_num==nil) or (oldest_img_dir==nil)) then  -- get first image/DCIM folder from this run
                        oldest_img_num = get_exp_count()
                        oldest_img_dir = string.sub(get_image_dir(),8,15)
                        printf(string.format(" Oldest image: %s/IMG_%04d.JPG",oldest_img_dir,oldest_img_num))
                    end
                    shot_counter = shot_counter+1
                    fstop = av96_to_aperture(av96current)
                    if extended_log == true then
                        tv_calc = (bv96current+sv96current-av96current)
                        tv_comp = tv96current-tv_calc
                        if tv96current < 1 then tv_calc = (tv_calc+compensation)*exp_shift/16 end
                        if tv96current < 1 then
                            shotstring = string.format(',%s,%s, tv:,%s, f:,%d.%d, ISO:,%d, Tv96:,%d, Bv96:,%d, Sv96:,%d, Av96:,%d, compensation,%d, shift(Bv+Sv-Av+C):,%d', string.sub(get_image_dir(),8), shotstring, tv2seconds(tv96current), fstop/1000, (fstop%1000)/100, sv96_to_iso(sv96_real_to_market(sv96current)), tv96current, bv96current, sv96current, av96current, tv_comp, tv_calc)
                        else
                            shotstring = string.format(',%s,%s, tv:,%s, f:,%d.%d, ISO:,%d, Tv96:,%d, Bv96:,%d, Sv96:,%d, Av96:,%d, compensation,%d, (Bv+Sv-Av):,%d', string.sub(get_image_dir(),8), shotstring, tv2seconds(tv96current), fstop/1000, (fstop%1000)/100, sv96_to_iso(sv96_real_to_market(sv96current)), tv96current, bv96current, sv96current, av96current, tv_comp, tv_calc)
                        end
                    else
                        shotstring = string.format(',%s,%s, tv:,%s, f:,%d.%d, ISO:,%d, Tv96:,%d, Bv96:,%d, Sv96:,%d, Av96:,%d,,,,', string.sub(get_image_dir(),8), shotstring, tv2seconds(tv96current), fstop/1000, (fstop%1000)/100, sv96_to_iso(sv96_real_to_market(sv96current)), tv96current, bv96current, sv96current, av96current)
                    end
                else
                    shotstring = ",<no shot> ,,,,,,,,,,,,,,,,,,,"   -- camera is in night mode
                end
                local bvolts = get_vbatt()
                if (usb_shoot==true) then
                    shotstring = shotstring .. " >USB"
                    usb_shoot=false
                end
                if extended_log == true then
                    printf("%s, V:,%d.%3.3d, T:,%d, focus(mm):, %d", shotstring, bvolts/1000,bvolts%1000, get_temperature(0), get_focus())
                else
                    printf("%s, V:,%d.%3.3d, T:,%d", shotstring, bvolts/1000,bvolts%1000, get_temperature(0))
                end
                if (zoom_test == true) then update_zoom(zoom_setpoint) end     -- zoom tester
                if extended_log==true then
                    activate_display(3)      -- display off called 3s after shot to show status and turn off backlight before next shot
                else
                    activate_display(0)
                end
           end

        -- shut down camera if SD card is full
            if (jpg_count ~= nil) then
                if (jpg_count < 2 ) then
                    printf("SD card full - shutting down")
                    sleep(5000)
                    post_levent_to_ui('PressPowerButton')
                    sleep(10000)
                end
            end

        -- check for user input from the keypad (determines loop timing too)
            wait_click(100)

        until not( is_key("no_key"))

        if is_key("menu") then
            exit_request = true
            printf(" menu key exit\n")
        elseif not(is_key("remote")) then
            printf("key pressed")
            activate_display(30)                                -- reactivate display for 30 seconds
        end

    until exit_request

    restore()

-- eof --


