# Doll is a Mac app that help you catch up important messages!

In **macOS**, It feels really great when you hide the **Dock**, open a **full screen** window and focus on your task.

But we are not living in an ideal world, your teammates may need your help anytime, and when you are in focus mode, occasionally you just _**forgot to respond**_!

Message apps like **Mail**, **Slack** and **Microsoft Teams** don't even offer a **_menu bar icon_** at all, so if you're working in a full screen window, or looking at another extra Monitor screen which can't show the Dock, there is no way you will notice the unread messages!

![Basic usage](./Doll/Docs/Images/dock-only.png)
 
(Sorry the notification center did notice you, but they will soon dismiss after a short period, if you miss that, you miss the message)

![Notification center](./Doll/Docs/Images/notification.png)

It would be great if we could put the icon and badge of these apps into the **_Menu bar_**, that way we can always easily notice new messages across screens, just like this:

![Show case](./Doll/Docs/Images/showcase.png)

# Doll?
In my favor animation [《Darker than dark》](https://en.wikipedia.org/wiki/Darker_than_Black), if a **_Contractor_** use his power and never willing to pay the cost, eventually he will lose control of his power, become an emotionless **_Doll_**.

If we use too much **focus power** without paying the cost, what will we become >>__<<.

# Install
You can download the latest dmg file from [here](https://github.com/xiaogdgenuine/Doll/releases/latest)
Minimum system requirement: **_macOS 11.0_** (Big Sur)

## Local build with pending fixes

This fork combines three upstream PRs in `codex/fullscreen-fixes`:

- [#75](https://github.com/xiaogdgenuine/Doll/pull/75) (`c006f4b`, duy84): use a non-activating panel for full-screen alerts to avoid taking keyboard focus on macOS 27.
- [#71](https://github.com/xiaogdgenuine/Doll/pull/71) (`18c581e`, stavfx): preserve menu-bar icon positions when hiding and showing them.
- [#70](https://github.com/xiaogdgenuine/Doll/pull/70) (`70c6704`, seemuch): allow spacing between an icon and its notification count.

Build with macOS Command Line Tools and Python 3.9 or later:

```sh
python3 scripts/build-local.py
```

The script downloads the exact dependency revisions in `Package.resolved`, builds
the app and login helper from source, packages images and translations, and signs
both executables ad hoc. Full Xcode is not required. This build targets macOS 12+
and the architecture of the build machine. Output: `build/Doll.app` and
`build/Doll-0.0.9.3-arm64.zip` on Apple Silicon. The original Xcode project remains
available for normal Xcode builds.

When installed, SDK 26.5 is preferred because Command Line Tools 27 lack the
SwiftUI macro plugin required by SDK 27. Set `DOLL_SDKROOT` to override this selection.

Quit the installed Doll, then replace it with the new app in Applications. The
bundle identifier is unchanged, so existing settings are reused. macOS may require
you to grant Accessibility access again after replacing the signed app. The local
build is not notarized.

After installation, enable **Show alert in full screen mode**, type in a full-screen
app, and trigger a new badge in a monitored app. Check that typing continues, the
alert disappears after three seconds, and clicking it opens the monitored app.
Also check two-digit counts and icon positions after hiding/showing icons and
restarting Doll. These interactive checks are separate from a successful build.

# How to use?
It's simple, click on "+" button at the left bottom corner, search and select the app you want to monitor:

![Add monitor](./Doll/Docs/Images/usage-0.png)

![Search and select](./Doll/Docs/Images/search-and-select.png)

Then Doll will ask for your permission to use the Accessibility API: 

![ask-for-permission.png](./Doll/Docs/Images/ask-for-permission.png)

Please make sure you grant that permission to **Doll.app** otherwise nothing will be monitored!

![grant-permission.png](./Doll/Docs/Images/grant-permission.png)

Done, you are all setup!
Doll now will monitor all the badge update in the Dock, and sync the numbers into the menu bar!

![running.png](./Doll/Docs/Images/running.png)

Doll also can show new notification as red badge, just like in dock!

![show as badge](./Doll/Docs/Images/show-as-badge.png)

# I want to change the Monitor apps
If the monitored app is running, click on the menu bar icon will simply open that app.

But if you want to change stuffs, use right click, or left click while holding the "**_Option key(⌥)_**".

![config.png](./Doll/Docs/Images/config.png)

# Security concern about the permission?
**_Never! Ever! Trust! Anybody! in Internet!_**

**Doll** is open source, you are free to download, review, modify and compile your own version of the app, go ahead and happy coding~


# How the app works?
**Doll** utils the [macOS Accessibility API](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/OSXAXmodel.html#//apple_ref/doc/uid/TP40001078-CH208-TPXREF101), it will sync the latest badge text to menu bar from every Monitored app in the **Dock** element.

Due to the limitation of Accessibility API(Can't watch for element's attribute value change), Doll has to sync badges by every second(Yep, the infamy **_Polling_** style).

But don't worry about the performance, after all the synchronization happens only 86400 times per day, and all it does is just read and set few element's text, that's an operation executed less than **1ms**!

If you found any potential Bug or Performance issue, feel free to submit a PR!

# Love this app?
<a href="https://www.buymeacoffee.com/xiaogd" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/arial-yellow.png" alt="Buy Me A Coffee" width="217px" ></a>
