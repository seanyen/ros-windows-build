@echo off
:: ignore the errors from rosdep install
rosdep install --from-paths c:\colcon_ws\src --ignore-src --rosdistro %ROS_DISTRO% -r -y
exit /b 0