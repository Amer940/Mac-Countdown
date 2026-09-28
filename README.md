--- How to install menu bar app

1. Locate the file you downloaded from this repo
2. Run bash ~/{{location of your file}} - most probably it will be "bash ~/Downloads/install-goal-countdown.sh"
3. That is it, you can now set your goal and name it in the menu bar 

--- How to delete menu bar app

```
  pkill -x GoalCountdown
  osascript -e 'tell application "System Events" to delete (every login item whose name is "GoalCountdown")'
  rm -rf ~/Applications/GoalCountdown.app
  defaults delete local.goalcountdown
```

--- How to install widget app

1. Locate the file you downloaded from this repo named "install-goal-widget.sh"
2. Run bash command - most probably the "bash ~/Downloads/install-goal-widget.sh"
3. That is it, add it as a widget on desktop. It's under category name "GoalWidget"

--- How to delete widget app

```
  rm -rf /Applications/GoalWidget.app ~/GoalWidget
```
