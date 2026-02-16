<p align="center">
  <img src="https://raw.githubusercontent.com/tisfeng/ImageBed/main/uPic/icon_512x512@2x.png" height="256">
  <h1 align="center">Easydict</h1>
  <h4 align="center">macOS Dictionary & AI Translation App</h4>
<p align="center"> 
<a href="https://github.com/iTvX/Easydict/blob/main/LICENSE">
<img src="https://img.shields.io/github/license/iTvX/Easydict"
            alt="License"></a>
<a href="https://github.com/iTvX/Easydict/releases">
<img src="https://img.shields.io/github/downloads/iTvX/Easydict/total.svg"
            alt="Downloads"></a>
<a href="https://img.shields.io/badge/-macOS-black?&logo=apple&logoColor=white">
<img src="https://img.shields.io/badge/-macOS-black?&logo=apple&logoColor=white"
            alt="macOS"></a>  
</p>

<div align="center">
<a href="./README_ZH.md">中文</a> &nbsp;&nbsp;|&nbsp;&nbsp; <a href="./README.md">English</a>
</div>

## Easydict

`Easydict` is an independent macOS dictionary and AI translation app focused on fast word lookup and multilingual AI-assisted translation.

It is designed for daily productivity on macOS, with input translation, select-to-translate, OCR screenshot translation, and multi-service querying in one app.

Easydict is ready to use out of the box, can automatically recognize the language of the input text, supports input translate, select translate, and OCR screenshot translate, and can query multiple translation services results at the same time.

**Supported translation services:** [**🍎 Apple Dictionary**](./docs/en/How-to-use-macOS-system-dictionary-in-Easydict.md), [🍎 **Apple Translate**](./docs/en/How-to-use-macOS-system-translation-in-Easydict.md), [OpenAI](https://chat.openai.com/), [Gemini](https://gemini.google.com/), [DeepSeek](https://www.deepseek.com/), [Ollama](https://ollama.com/), [Groq](https://groq.com/), [Zhipu AI](https://open.bigmodel.cn/), [GitHub Models](https://github.com/marketplace/models), [DeepL](https://www.deepl.com/translator), [Google](https://translate.google.com), [Youdao](https://www.youdao.com/), [Tencent](https://fanyi.qq.com/), [Bing](https://www.bing.com/translator), [Baidu](https://fanyi.baidu.com/), [Niutrans](https://niutrans.com/), [Caiyun](https://fanyi.caiyunapp.com/), [Alibaba](https://translate.alibaba.com/), [Volcano](https://translate.volcengine.com/translate) and [Doubao](https://www.volcengine.com/docs/82379/1820188).

![Log](https://raw.githubusercontent.com/tisfeng/ImageBed/main/uPic/Log-1688378715.png)

<table>
    <td> <img src="https://raw.githubusercontent.com/tisfeng/ImageBed/main/uPic/iShot_2023-05-28_16.32.18-1685262784.png">
    <td> <img src="https://raw.githubusercontent.com/tisfeng/ImageBed/main/uPic/iShot_2023-05-28_16.32.26-1685262803.png">
</table>

![immerse-1686534718.gif](https://raw.githubusercontent.com/tisfeng/ImageBed/main/uPic/immerse-1686534718.gif)

## Features

- 🚀 Out of the box, automatic language recognition
- 🖱️ Auto select with mouse and shortcut key
- 📸 OCR screenshot translation and slient screenshot OCR
- 🔊 Multiple TTS voice services
- 📚 Support 🍎 [Apple System Dictionary](./docs/en/How-to-use-macOS-system-dictionary-in-Easydict.md) and [System Translation](./docs/en/How-to-use-macOS-system-translation-in-Easydict.md)
- 🌐 Support 20+ translation services (OpenAI, Gemini, DeepL, Google, Ollama, Groq, etc.)
- 🗣️ Support for 48 languages

**If you like this app, please consider giving it a [Star](https://github.com/iTvX/Easydict) ⭐️, thanks! (^-^)**

## Contributing

If you're interested in this project, we welcome your contributions. Our development follows this workflow:

- **dev branch**: Latest development code, may contain features in progress
- **main branch**: Stable release code, regularly merged from dev branch

Please submit bug fixes and features to dev branch; for major new features or UI changes, please open an issue for discussion first. See [full contribution guide](./docs/en/GUIDE.md#contributor-guide).

## Issue/PR Triage Notes

The maintainer has been quite busy recently and usually only has time to triage issues on weekends. PRs (especially bugfix PRs) are prioritized. Also, due to an overloaded inbox and notifications, some messages may not be seen or replied to promptly. Thanks for your understanding.

## Installation

### Homebrew Installation (Recommended)

```bash
brew install --cask easydict
```

### Manual Installation

[Download](https://github.com/iTvX/Easydict/releases) the latest release.

> [!NOTE]
> Latest version supports macOS 13.0+, for older systems please use [2.7.2](https://github.com/iTvX/Easydict/releases/tag/2.7.2)

---

## Usage

| Ways                      | Description                                                                                                                                  | Preview                                                                                                                                        |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Input Translate           | Press the input translate shortcut key (default `⌥ + A`), enter the text to be translated, and `Enter` key to translate          | ![iShot_2023-01-20_11.28.46-1674185354](https://raw.githubusercontent.com/tisfeng/ImageBed/main/uPic/iShot_2023-01-20_11.28.46-1674185354.gif) |
| Mouse Select Translate    | The query icon is automatically displayed after the word is selected, and the mouse hovers over it to query                                  | ![iShot_2023-01-20_11.01.35-1674183779](https://raw.githubusercontent.com/tisfeng/ImageBed/main/uPic/iShot_2023-01-20_11.01.35-1674183779.gif) |
| Shortcut Select Translate | After selecting the text to be translated, press the shortcut key (default `⌥ + D`)                                                          | ![iShot_2023-01-20_11.24.37-1674185125](https://raw.githubusercontent.com/tisfeng/ImageBed/main/uPic/iShot_2023-01-20_11.24.37-1674185125.gif) |
| Screenshot Translate      | Press the screenshot translate shortcut key (default `⌥ + S`) to capture the area to be translated                                           | ![iShot_2023-01-20_11.26.25-1674185209](https://raw.githubusercontent.com/tisfeng/ImageBed/main/uPic/iShot_2023-01-20_11.26.25-1674185209.gif) |
| Silent Screenshot OCR     | Press the Silent Screenshot shortcut key（default `⌥ + ⇧ + S`）to capture the area, the OCR results will be copied directly to the clipboard | ![屏幕录制 2023-05-20 22 39 11](https://github.com/Jerry23011/Easydict/assets/89069957/c16f3c20-1748-411e-be04-11d8fe0e61af)                     |

---

## Documentation

- 📖 [Complete Usage Guide](./docs/en/GUIDE.md) - Detailed features, configuration and tips
- 🔧 [Developer Build Guide](./docs/en/GUIDE.md#developer-build) - Build and run from source code
- 🍎 [How to use macOS System Dictionary](./docs/en/How-to-use-macOS-system-dictionary-in-Easydict.md)
- 🍎 [How to use macOS System Translation](./docs/en/How-to-use-macOS-system-translation-in-Easydict.md)
- 🌍 [How to translate Easydict](./docs/How-to-translate-Easydict-en.md)

---

## Acknowledgements

- This project was inspired by [saladict](https://github.com/crimx/ext-saladict) and [Bob](https://github.com/ripperhe/Bob), and the initial version was made based on [Bob (GPL-3.0)](https://github.com/1xiaocainiao/Bob). Easydict has made many improvements and optimizations on the original project, and many features and UI are referenced from Bob.
- Screenshot feature is based on [isee15](https://github.com/isee15)'s [Capture-Screen-For-Multi-Screens-On-Mac](https://github.com/isee15/Capture-Screen-For-Multi-Screens-On-Mac), and optimized on this project.
- Select text feature is referenced from [PopClip](https://pilotmoon.com/popclip/).

## Statement

Easydict is licensed under the [GPL-3.0](https://github.com/iTvX/Easydict/blob/main/LICENSE) open source license, which is for learning and communication only. Anyone can get this product and source code for free. If you believe that your legal rights have been violated, please contact the [author](https://github.com/iTvX) immediately. You can use the source code freely, but you must attach the corresponding license and copyright.
