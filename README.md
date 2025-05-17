# Raytracing ReSTIR Implementation

![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202505011544661.png)

## Usage

D3D12RaytracingReSTIR.exe [...]
* [-forceAdapter \<ID>] - create a D3D12 device on an adapter <ID>. Defaults to adapter 0
* [-vsync] - renders with VSync enabled
* [-disableUI] - disables GUI rendering

> The sample defaults to 1080p window size and 1080p RTAO. In practice, AO is done at quarter resolution as the 4x performance overhead generally doesn't justify the quality increase, especially on higher resolutions/dpis. Therefore, if you switch to higher window resolutions, such as 4K, also switch to quarter res RTAO via QuarterRes UI option to improve the performance.

### UI
The title bar of the sample provides runtime information:
* Name of the sample
* Frames per second
* GPU[ID]: name

The GUI menu in the top left corner provides a runtime information and a multitude of dynamic settings for the Scene, RTAO and the Denoiser components. 
* UP/DOWN - navigate among the settings 
* LEFT/RIGHT - change the setting
* Backspace - toggles the settings menu ON/OFF. If "Display Profiler" is enabled, it toggles between settings menu and a profiler UI.

In the Scene menu, you can change the following settings for ReSTIR:

* **Enable Temporal Reuse** - toggles Temporal Reuse ON/OFF
* **Enable Spatial Reuse** - toggles Spatial Reuse ON/OFF
* **WRS Reservoir Size** - sets the size of the reservoir for Weighted Reservoir Sampling. The default value is 32.


### Controls
* ALT+ENTER - toggles between windowed and fullscreen modes
* W,S - moves camera forward and back
* A,D - moves camera to the side
* Shift - toggles camera movement amplitude
* Hold left mouse key and drag - rotate camera's focus at position
* Hold right mouse key and drag - rotate scene
* L - enable/disable light animation
* C - enable/disable camera animation
* T - toggles scene animation
* 0 - Toggles Ground Truth spp vs 1 spp and switches to raw RTAO visualization
* 1 - Raw/single frame RTAO visualization
* 2 - Denoised RTAO visualization
* 3 - ReSTIR + Specular PBR Pathtracer + RTAO visualization
* 4 - Toggles RTAO ray lengths - short | long
* ENTER - Toggles RTAO ON/OFF in "Specular PBR Pathracer + RTAO visualization mode"
* F9 - does a profiling pass. Renders 1000 frames, rotates camera 360 degrees and outputs GPU times to Profile.csv
* space - pauses/resumes rendering
* U/Y - moves car by the house back and forth
* J/M - moves spaceship up and down
* H/K - rotates spaceship around scene's center
* ESC - terminate the application

## TODO List

### Preparation
- [x] Build and run the DX12 sample: `D3D12RaytracingRealTimeDenoisedAmbientOcclusion`
    - Press key 3 to enter PBR path tracer mode — this will be the base for modifications
- [x] Learn the basics of ReSTIR
    - https://intro-to-restir.cwyman.org
    - https://cs.dartmouth.edu/~wjarosz/publications/bitterli20spatiotemporal.html

### Baseline Setup
- [x] Modify the test scene:
    - [x] Generate Area Lights (currently only directional light is used)
    - [x] Pass Area Lights data to the shader
- [x] Update the existing path tracer:
    - [x] Add support for sampling from Area Lights
    - This will serve as the baseline for comparison with ReSTIR

### Implement ReSTIR
- [x] Integrate ReSTIR into the path tracer mode.
    - [x] Weighted Reservoir Sampling.
    - [x] Spatial Reuse Shader.
    - [x] Temporal Reuse Shader.
    - [x] Shade Pixel.

### Future Work
- [ ] Improving or extending the `GenerateAreaLights` function.
- [ ] PBRT Light Loading
- [ ] Invisible Light Sources

### Test Variants & Tuning
- [x] Experiment with different ReSTIR parameters (e.g. reservoir size.)
- [x] Compare performance and quality across different settings and baselines
- [ ] Modify the default scene
    - Add or adjust geometry from https://github.com/wallisc/DuosRenderer/tree/DXRRenderer/Assets
## Screenshots

### Ray Tracing
![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202504302051876.png)
### Temporal Reuse
![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202504302054306.png)
### Spatial Reuse
![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202504302056460.png)
### Resolve
![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202504302056316.png)
### Performance
![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202504302057647.png)
### Scene Comparison
![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202504302035894.png)

![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202504302035302.png)

![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202504302035304.png)

![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202504302036152.png)

![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202504302039122.png)

![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202504302040984.png)

![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202504302040484.png)

![](https://raw.githubusercontent.com/NothingToSay0031/Images/main/202504302040758.png)




# DirectX-Graphics-Samples
This repo contains the DirectX 12 Graphics samples that demonstrate how to build graphics intensive applications for Windows 10.

We invite you to join us at our [discord server](http://discord.gg/directx). See our [YouTube channel](https://www.youtube.com/MicrosoftDirectX12andGraphicsEducation) for tutorials, our [spec repo](https://microsoft.github.io/DirectX-Specs/) for engineering specs of our features and [devblogs](https://devblogs.microsoft.com/directx/) for blog posts. Follow us on Twitter [@DirectX12](https://twitter.com/directx12) for the latest! See the [related links](#related-links) section for our full list of DX12-related links.

Finally, make sure that you visit the [DirectX Landing Page](https://devblogs.microsoft.com/directx/landing-page/) for more resources for DirectX developers.

## API Samples
In the Samples directory, you will find samples that attempt to break off specific features and specific usage scenarios into bite-sized chunks. For example, the ExecuteIndirect sample will show you just enough about execute indirect to get started with that feature without diving too deep into multiengine whereas the nBodyGravity sample will delve into multiengine without touching on the execute indirect feature etc. By doing this, we hope to make it easier to get started with DirectX 12.

### DirectX 12 Ultimate samples
1. [D3D12 Mesh Shaders](Samples/Desktop/D3D12MeshShaders/readme.md): This sample demonstrates how Mesh shaders can be used to increase the flexibility and performance of the geometry pipeline.
    
    <img src="Samples/Desktop/D3D12MeshShaders/src/MeshletRender/Screenshot_DX12U.png" alt="D3D12 Meshlet Render preview" height="200">

1. [D3D12 Variable Rate Shading](Samples/Desktop/D3D12VariableRateShading/readme.md): This sample demonstrates how shading rate can be reduced with little or no reduction in visual quality, leading to “free” performance.
    
    <img src="Samples/Desktop/D3D12VariableRateShading/src/Screenshot_DX12U.png" alt="D3D12 Variable Rate Shading GUI" height="200">

1. [D3D12 Raytracing](Samples/Desktop/D3D12Raytracing/readme.md): This sample demonstrates how DirectX Raytracing (DXR) brings a new level of graphics realism to video games, previously only achievable in the movie industry.
    
    <img src="Samples/Desktop/D3D12Raytracing/src/D3D12RaytracingRealTimeDenoisedAmbientOcclusion/Screenshot_DX12U.png" alt="D3D12 Raytracing Real-Time Denoised Ambient Occlusion preview" height="200">

## MiniEngine: A DirectX 12 Engine Starter Kit
In addition to the samples, we are announcing the first DirectX 12 preview release of the MiniEngine.

It came from a desire to quickly dive into graphics and performance experiments.  We knew we would need some basic building blocks whenever starting a new 3D app, and we had already written these things at countless previous gigs.  We got tired of reinventing the wheel, so we established our own core library of helper classes and platform abstractions.  We wanted to be able to create a new app by writing just the Init(), Update(), and Render() functions and leveraging as much reusable code as possible.  Today our core library has been redesigned for DirectX 12 and aims to serve as an example of efficient API usage.  It is obviously not exhaustive of what a game engine needs, but it can serve as the cornerstone of something new.  You can also borrow whatever useful code you find.

### Some features of MiniEngine
* High-quality anti-aliased text rendering
* Real-time CPU and GPU profiling
* User-controlled variables
* Game controller, mouse, and keyboard input
* A friendly DirectXMath wrapper
* Perspective camera supporting traditional and reversed Z matrices
* Asynchronous DDS texture loading and ZLib decompression
* Large library of shaders
* Easy shader embedding via a compile-to-header system
* Easy render target, depth target, and unordered access view creation
* A thread-safe GPU command context system (WIP)
* Easy-to-use dynamic constant buffers and descriptor tables

## Requirements
Some samples require support for DirectX 12 Ultimate, see [this](http://aka.ms/DirectX12UltimateDev) post for details.
### Master branch
This branch is intended for the latest [released](https://docs.microsoft.com/en-us/windows/release-information/) Windows 10 version.
* Windows 10 version 2004 (no new features were added in version 20H2)
* [Visual Studio 2019](https://www.visualstudio.com/) with the [Windows 10 SDK version 2004(19041)](https://developer.microsoft.com/en-US/windows/downloads/windows-10-sdk)
### Develop branch
This branch is intended for features available in the latest Windows Insider Preview
* [Windows 10 Insider Preview builds](https://docs.microsoft.com/en-us/windows-insider/developers/get-started) ([Dev Channel](https://docs.microsoft.com/en-us/windows-insider/flighting))
* [Visual Studio 2019](https://www.visualstudio.com/) with the [Windows 10 Insider Preview SDK](https://www.microsoft.com/en-us/software-download/windowsinsiderpreviewSDK)

## Contributing
We're always looking for your help to fix bugs and improve the samples.  File those pull requests and we'll be happy to take a look.

Troubleshooting information for this repository can be found in the site [Wiki](https://github.com/Microsoft/DirectX-Graphics-Samples/wiki).

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Related links
* [DirectX Developer Blog](https://devblogs.microsoft.com/directx)
* [DirectX API documentation](https://docs.microsoft.com/en-us/windows/win32/directx)
* [PIX on Windows](https://devblogs.microsoft.com/pix/documentation/)
* [D3DX12 (the D3D12 Helper Library)](https://github.com/Microsoft/DirectX-Graphics-Samples/tree/master/Libraries/D3DX12)
* [D3D12 Raytracing Fallback Layer](https://github.com/Microsoft/DirectX-Graphics-Samples/tree/master/Libraries/D3D12RaytracingFallback)
* [D3D12 Residency Starter Library](https://github.com/Microsoft/DirectX-Graphics-Samples/tree/master/Libraries/D3DX12Residency)
* [D3D12 MultiGPU Starter Library](https://github.com/Microsoft/DirectX-Graphics-Samples/tree/master/Libraries/D3DX12AffinityLayer)
* [DirectX Tool Kit](https://github.com/Microsoft/DirectXTK12)
* [D3DDred debugger extension](https://github.com/Microsoft/DirectX-Debugging-Tools)
