# Required: add an alarm sound file here

The stillness-alert feature (`StillnessAlarmController` in
`lib/features/emergency/stillness_check_dialog.dart`) plays
`assets/sounds/alarm.mp3` on a loop during the "Are you okay?" countdown.

This repo does not include an actual audio file (binary asset — add your own).

Steps:
1. Get a loud, looping-friendly alarm/siren `.mp3` (a few seconds long is fine —
   it's played on loop). Many royalty-free options exist, e.g. pixabay.com/sound-effects,
   search "alarm siren".
2. Save it as `assets/sounds/alarm.mp3` (exact name/path).
3. Run `flutter pub get` after adding it.

If this file is missing, the vibration + full-screen dialog + notification
will still work — only the looped alarm sound will silently fail to play
(audioplayers throws on missing asset; the code catches that so playback
failure doesn't crash the alert, but you also won't hear anything until you
add the file).
