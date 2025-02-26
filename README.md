**If you are new to low-level graphics programming or you would like to learn about zig-gamedev framework I recommend starting with [intro applications](https://github.com/michal-z/zig-gamedev/tree/main/samples/intro).**

# zig-gamedev project

This repository contains a collection of [sample applications](#sample-applications) and libraries written in **[Zig programming language](https://ziglang.org/)**. Prebuilt binaries for all sample applications can be found in [Releases](https://github.com/michal-z/zig-gamedev/releases). Project is under active development, see [Roadmap](https://github.com/michal-z/zig-gamedev/wiki/Roadmap) and [Progress Reports](https://github.com/michal-z/zig-gamedev/wiki/Progress-Reports) for the details.<br />

*I build game development stuff in Zig full-time. As a sample of my work please see [this video](https://www.youtube.com/watch?v=1hYIzFVdA2o). If you like my project and my mission to promote the language, please consider [supporting me](https://github.com/sponsors/michal-z).*

#### Some features and libraries we develop:

* Zero dependency except [Zig compiler (master)](https://ziglang.org/download/) - no Visual Studio/Build Tools/Windows SDK is needed - this repo + Zig compiler package (60 MB) is enough to start developing (any debugger can be used)
* Building is as easy as running `zig build` (see: [Building](#building-sample-applications))
* [zmath](https://github.com/michal-z/zig-gamedev/blob/main/libs/zmath) - fast SIMD math library for game developers (**fully cross-platform**)
* [zbullet](https://github.com/michal-z/zig-gamedev/blob/main/libs/zbullet) - Zig bindings and C API for [Bullet physics library](https://github.com/bulletphysics/bullet3) (**fully cross-platform**)
* [zwin32](https://github.com/michal-z/zig-gamedev/blob/main/libs/zwin32) - standalone Zig bindings for Win32 API
* [zd3d12](https://github.com/michal-z/zig-gamedev/blob/main/libs/zd3d12) - helper library for working with DirectX 12
* [zxaudio2](https://github.com/michal-z/zig-gamedev/blob/main/libs/zxaudio2) - helper library for working with XAudio2
* [zpix](https://github.com/michal-z/zig-gamedev/blob/main/libs/zpix) - support for GPU profiling with PIX
* [ztracy](https://github.com/michal-z/zig-gamedev/blob/main/libs/ztracy) - support for CPU profiling with [Tracy](https://github.com/wolfpld/tracy)
* Interop with Direct2D and DirectWrite for high-quality vector graphics and text rendering (optional)
* Uses some great C/C++ libraries which are seamlessly built by `zig cc` compiler (see: [libs/common/src/c](libs/common/src/c))

## Sample applications

Some of the sample applications are listed below. More can be found in [samples](samples/) directory.

1. [rasterization](samples/rasterization): This sample application shows how GPU rasterizes triangles in slow motion.

    <a href="samples/rasterization"><img src="samples/rasterization/screenshot.png" alt="rasterization" height="200"></a>

1. [physically based rendering](samples/physically_based_rendering): This sample implements physically based shading and image based lighting to achive realistic looking rendering results.

    <a href="samples/physically_based_rendering"><img src="samples/physically_based_rendering/screenshot.png" alt="physically based rendering" height="200"></a>

1. [simple raytracer](samples/simple_raytracer): This sample implements basic hybrid renderer. It uses rasterization to resolve primary rays and raytracing (DXR) for shadow rays.

    <a href="samples/simple_raytracer"><img src="samples/simple_raytracer/screenshot.png" alt="simple raytracer" height="200"></a>

1. [mesh shader test](samples/mesh_shader_test): This sample shows how to use DirectX 12 Mesh Shader.

    <a href="samples/mesh_shader_test"><img src="samples/mesh_shader_test/screenshot.png" alt="mesh shader test" height="200"></a>

1. [virtual physics lab](samples/bullet_physics_test): This sample application demonstrates how to use full 3D physics engine in your Zig programs.

    <a href="samples/bullet_physics_test"><img src="samples/bullet_physics_test/screenshot1.png" alt="virtual physics lab" height="200"></a>

1. [audio playback test](samples/audio_playback_test): This sample demonstrates how to decode .mp3 file using Microsoft Media Foundation and play it back using Windows Audio Session API (WASAPI).

    <a href="samples/audio_playback_test"><img src="samples/audio_playback_test/screenshot.png" alt="audio playback test" height="200"></a>

1. [DirectML convolution test](samples/directml_convolution_test): This sample demonstrates how to perform GPU-accelerated convolution operation using DirectML.

    <a href="samples/directml_convolution_test"><img src="samples/directml_convolution_test/screenshot.png" alt="directml convolution test" height="200"></a>

## Building sample applications

To build all sample applications (assuming `zig.exe` is in the PATH and [Git LFS](https://git-lfs.github.com/) is installed):

1. `git clone https://github.com/michal-z/zig-gamedev.git`
1. `cd zig-gamedev`
1. `zig build`

Build artifacts will show up in `zig-out/bin` folder.

`zig build <sample_name>` will build sample application named `<sample_name>`.

`zig build <sample_name>-run` will build and run sample application named `<sample_name>`.

`zig build <sample_name>-dxc` will build shaders for sample application named `<sample_name>`.

To list all available sample names run `zig build --help` and navigate to `Steps` section.

As mentioned above, the only dependency needed to build this project is [Zig compiler](https://ziglang.org/download/), neither Visual Studio nor Windows SDK has to be installed.

Zig compiler consists of a single ~60MB .zip file that needs to be downloaded separately. Latest development build of the compiler must be used (master) you can download prebuilt binaries [here](https://ziglang.org/download/).

#### Build options

All sample applications support the following build options:

* `-Drelease-safe=[bool]` - Optimizations on and safety on
* `-Drelease-fast=[bool]` - Optimizations on and safety off
* `-Denable-pix=[bool]` - PIX markers and events enabled
* `-Denable-dx-debug=[bool]` - Direct3D 12, Direct2D, DXGI debug layers enabled
* `-Denable-dx-gpu-debug=[bool]` - Direct3D 12 GPU-Based Validation enabled (requires -Denable-dx-debug=true)
* `-Dtracy=[path/to/tracy/source]` - [Tracy](https://github.com/wolfpld/tracy) profiler zones enabled

#### Examples

`zig build -Denable-dx-debug=true -Drelease-fast=true`

`zig build -Dtracy="C:/Development/tools/Tracy/tracy-0.7.8"`

`zig build simple_raytracer`

`zig build simple_raytracer-run`

`zig build simple_raytracer-dxc`

## Requirements

This project uses [DirectX 12 Agility SDK](https://devblogs.microsoft.com/directx/gettingstarted-dx12agility/) which allows to always use latest DirectX 12 features regardless of Windows version installed (this works from Windows 10 November 2019). In particular, following Windows versions are supported:

* Windows 10 May 2021 (Build 19043) or newer
* Windows 10 October 2020 (Build 19042.789+)
* Windows 10 May 2020 (Build 19041.789+)
* Windows 10 November 2019 (Build 18363.1350+)

## GitHub Sponsors
Thanks to all people who sponsor zig-gamedev project! In particular, these fine folks sponsor zig-gamedev for $25/month or more:
* [mzet (mzet-)](https://github.com/mzet-)
* Zig Software Foundation (ziglang)
* Ian (LinuXY)
* Simon A. Nielsen Knights (tauoverpi)
* shintales (shintales)
* Chris Heyes (hazeycode)
