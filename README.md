--- How to install

1. Locate the file you downloaded from this repo
2. Run bash ~/{{location of your file}} - most probably it will be "bash ~/Downloads/install-goal-countdown.sh"
3. That is it, you can now set your goal and name it in the menu bar 

--- How to delete

```
  pkill -x GoalCountdown
  osascript -e 'tell application "System Events" to delete (every login item whose name is "GoalCountdown")'
  rm -rf ~/Applications/GoalCountdown.app
  defaults delete local.goalcountdown
```
