# osxrdp - xrdp for macOS

- **Version:** 3.1.1
- **Author:** kyle
- **GitHub:** [github.com/kyle-kw/osxrdp](https://github.com/kyle-kw/osxrdp)

## Overview
osxrdp is an unofficial module of xrdp to support rdp server in macOS.
<img width="1282" height="832" alt="OSXRDP" src="https://github.com/user-attachments/assets/539b2870-b5c6-4d16-90b0-ad6d2799951a" />

<h6><a href="https://www.youtube.com/watch?v=ltxx2bha5-8">Video</a></h6>

## Features
|Features|Status|
|------|---|
|Smooth Remote Control (H.264)|✅|
|Virtual monitor (for dynamic resolution)|✅|
|Remote control for non logoned macOS user|✅|
|Basic Clipboard (Text)|✅|
|Advanced Clipboard (Image, Rich Text)|✅|
|Multiple monitor (only H.264)|✅|
|File transfer| ✅ |
|Audio|❌|


## Manual
<h6><a href="Manual.md">Link</a></h6>

## Limitation
* osxrdp is still in beta version. It may contain numerous bugs and is not suitable for production use.

## Supported OS
macOS 12.4 or higher version.\
Support Apple Silicon & Intel mac.

## Unit tests
On macOS (Xcode CLI tools):

```bash
bash tests/run_unit_tests.sh
```

GitHub Actions runs this suite **before** the unsigned package build.

## Etc
osxrdp is compatible with original xrdp v0.10.6.1 version. (no modificated)
