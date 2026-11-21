import Foundation

/// English versions of every "?" explanation. Same keys as HelpTexts.zh.
extension HelpTexts {
    static let en: [String: HelpEntry] = {
        var d: [String: HelpEntry] = [:]

        // MARK: General
        d["layers"] = HelpEntry(
            title: "Adjustment layers",
            what: "Each layer is one grading tool, and you can stack as many as you like. Lower layers are applied first, upper layers last — just like Photoshop adjustment layers.",
            tip: "Drag layers to reorder. Click the eye to hide one for a quick comparison. Right-click to duplicate or delete.")
        d["histogram"] = HelpEntry(
            title: "Histogram",
            what: "Shows how many pixels sit at each brightness, from darkest (left) to brightest (right). The line is overall luminance; the colored areas are the red, green and blue channels.",
            tip: "A hill piled on the left means a dark photo, on the right a bright one. A hill cut off at either edge means crushed blacks or blown highlights.")
        d["opacity"] = HelpEntry(
            title: "Opacity",
            what: "How strongly this layer is applied — a discount on the whole effect.",
            up: "The full effect is shown.",
            down: "The effect fades, getting closer to how the photo looked without this layer.",
            tip: "Grading is easy to overdo. Pulling opacity down to 60–80% often looks more natural.")
        d["export.quality"] = HelpEntry(
            title: "Quality",
            what: "How much JPEG / HEIC files are compressed.",
            up: "Sharper, more detail, bigger files.",
            down: "Smaller files, but smooth areas like skies may show blocky banding.",
            tip: "85–92 is plenty for everyday sharing; you can hardly see the difference.")

        // MARK: Basic · White balance
        d["basic.temperature"] = HelpEntry(
            title: "Temperature",
            what: "Makes the whole photo cooler (blue) or warmer (yellow).",
            up: "Warmer and more golden, like late-afternoon sun. Feels cozy and nostalgic.",
            down: "Cooler and bluer, like an overcast morning. Feels calm, quiet and distant.",
            tip: "First make something that should be white or gray look neutral, then nudge toward the mood you want.")
        d["basic.tint"] = HelpEntry(
            title: "Tint",
            what: "Pushes the photo toward green or magenta. Mostly used to fix color casts from artificial light.",
            up: "More magenta and pink. Skin looks rosier; the mood gets dreamy and sweet.",
            down: "More green, like under fluorescent tubes. Fresh in small doses, sickly in large ones.",
            tip: "Indoor shots under office lighting often lean green — a small push to the right fixes it.")

        // MARK: Basic · Light
        d["basic.exposure"] = HelpEntry(
            title: "Exposure",
            what: "Overall brightness, measured in stops like a camera. +1 means twice as bright.",
            up: "Everything gets brighter. Too much turns skies and white walls into blank white.",
            down: "Everything gets darker — heavier and moodier. Too much turns shadows into mud.",
            tip: "Set overall brightness with Exposure first, then refine with Highlights and Shadows.")
        d["basic.contrast"] = HelpEntry(
            title: "Contrast",
            what: "How far apart the brights and darks are.",
            up: "Brights get brighter and darks darker. The image feels punchier and colors get richer.",
            down: "Tones move closer together. The image softens and turns gray — a gentle, airy look.")
        d["basic.highlights"] = HelpEntry(
            title: "Highlights",
            what: "Adjusts only the bright parts — skies, clouds, lit surfaces.",
            up: "Bright areas get brighter and the photo feels more open, but sky detail can get lost.",
            down: "Pulls bright areas down and brings back detail in skies and clouds. The photo feels calmer.",
            tip: "For any photo with sky, pulling Highlights left almost always helps.")
        d["basic.shadows"] = HelpEntry(
            title: "Shadows",
            what: "Adjusts only the dark parts — backlit faces, shade under trees, corners.",
            up: "Dark areas open up and reveal detail. The photo feels flatter and more relaxed.",
            down: "Dark areas get deeper, adding weight and drama.",
            tip: "For backlit portraits, push Shadows right and the face lights up.")
        d["basic.whites"] = HelpEntry(
            title: "Whites",
            what: "Sets how bright the very brightest point is. Works closer to pure white than Highlights.",
            up: "Brighter and cleaner. Too much blows out large areas.",
            down: "The brightest areas turn gray, as if behind a veil — a muted, vintage feel.")
        d["basic.blacks"] = HelpEntry(
            title: "Blacks",
            what: "Sets how dark the very darkest point is.",
            up: "Black lifts to dark gray — a faded film look.",
            down: "Deeper blacks. The image feels solid and strong; too much crushes the shadows.")

        // MARK: Basic · Texture
        d["basic.texture"] = HelpEntry(
            title: "Texture",
            what: "Emphasizes or smooths fine detail like pores, leaves, fabric and stone.",
            up: "Crisper, grittier detail — great for landscapes, architecture and character portraits.",
            down: "Fine lines smooth out and skin looks softer, without the plastic look of heavy retouching.",
            tip: "For portraits, −10 to −30 is a natural light skin smoothing.")
        d["basic.clarity"] = HelpEntry(
            title: "Clarity",
            what: "Boosts contrast along the edges of mid-sized shapes, making the image feel more three-dimensional.",
            up: "Stronger and more rugged. Too much creates halos and a dirty look.",
            down: "Softer, with a dreamy glow.")
        d["basic.dehaze"] = HelpEntry(
            title: "Dehaze",
            what: "Removes or adds atmospheric haze.",
            up: "Haze disappears, distant things get clearer, colors get richer.",
            down: "The scene fills with fog — soft, hazy and atmospheric.",
            tip: "On smoggy days, +20 to +40 helps a lot.")

        // MARK: Basic · Color
        d["basic.vibrance"] = HelpEntry(
            title: "Vibrance",
            what: "A “smart” saturation: it boosts only the muted colors and protects skin tones.",
            up: "More lively colors, without turning faces orange.",
            down: "Colors fade toward a refined, low-saturation look.",
            tip: "When you want more color, reach for Vibrance before Saturation.")
        d["basic.saturation"] = HelpEntry(
            title: "Saturation",
            what: "Makes every color stronger or weaker at once.",
            up: "Richer, louder colors. Too much looks cheap and fake.",
            down: "Paler colors. All the way left is black and white. Low saturation feels calm and literary.")

        // MARK: Basic · Detail
        d["basic.sharpen"] = HelpEntry(
            title: "Sharpening",
            what: "Makes edges crisper so the photo looks sharper.",
            up: "Sharper. Too much adds white halos and grain.",
            down: "Left as is.",
            tip: "A little (20–40) before export is enough. Check at 100%.")
        d["basic.noise"] = HelpEntry(
            title: "Noise reduction",
            what: "Removes the color speckles and grain in night shots and high-ISO photos.",
            up: "Cleaner and smoother. Too much looks waxy and detail disappears.",
            down: "Keeps the original grain and detail.")

        // MARK: Basic · Effects
        d["basic.vignette"] = HelpEntry(
            title: "Vignette",
            what: "Darkens or brightens the corners of the photo.",
            up: "Darker corners pull the eye to the center — focused, cinematic, nostalgic.",
            down: "Brighter corners — light, airy, dreamlike.")
        d["basic.grain"] = HelpEntry(
            title: "Grain",
            what: "Adds film-like grain.",
            up: "More visible grain — a film feel with gritty realism.",
            down: "Clean and digital.",
            tip: "Grain hides slight softness and noise. Vintage looks often use 20–40.")
        d["basic.grainSize"] = HelpEntry(
            title: "Grain size",
            what: "How big each grain is.",
            up: "Coarser grain, like high-speed film — rough and retro.",
            down: "Finer grain that just adds a hint of texture.")

        // MARK: What each layer does
        d["layer.curves"] = HelpEntry(
            title: "Curves",
            what: "The most flexible tone and color tool. The horizontal axis is the original brightness, the vertical axis the new one. Lift part of the line to brighten that range, lower it to darken.",
            tip: "Classic moves: an S-curve adds contrast; lifting the bottom-left point gives a faded-film black.")
        d["layer.levels"] = HelpEntry(
            title: "Levels",
            what: "Fix tones quickly with three handles — black point, midtone and white point. Simpler than Curves.",
            tip: "If a photo looks gray, press Auto or drag the black and white handles to the ends of the histogram.")
        d["layer.hueSaturation"] = HelpEntry(
            title: "Hue/Saturation",
            what: "Rotates every color, adjusts strength and lightness. Turn on Colorize to tint the whole image a single color.")
        d["layer.hsl"] = HelpEntry(
            title: "HSL mixer",
            what: "Adjusts eight colors separately — turn greens toward teal, deepen only the blue sky, brighten only skin. One of the most-used grading tools.")
        d["layer.colorBalance"] = HelpEntry(
            title: "Color balance",
            what: "Adds color separately to shadows, midtones and highlights. Teal shadows plus orange highlights is the classic movie look.")
        d["layer.selectiveColor"] = HelpEntry(
            title: "Selective color",
            what: "The printing-press approach: add or remove cyan, magenta, yellow and black ink in one family of colors (reds, whites, blacks…). Great for fine-tuning a single color.")
        d["layer.channelMixer"] = HelpEntry(
            title: "Channel mixer",
            what: "Builds new red, green and blue channels from a recipe of the original ones. Use it for infrared and color-swap effects, or high-quality black and white.")
        d["layer.blackWhite"] = HelpEntry(
            title: "Black & white",
            what: "Converts to black and white while letting you decide how bright each color becomes. Darken the blues and the sky turns dramatic.")
        d["layer.photoFilter"] = HelpEntry(
            title: "Photo filter",
            what: "Like putting a colored filter in front of the lens — washes the whole photo with a tone.")
        d["layer.gradientMap"] = HelpEntry(
            title: "Gradient map",
            what: "Recolors the photo by brightness: the darkest areas take the left color, the brightest take the right. Great for duotone posters and vintage tones.",
            tip: "Drop opacity to 20–40% for a subtle, unified tone.")
        d["layer.colorGrading"] = HelpEntry(
            title: "Color grading",
            what: "Three color wheels tint the shadows, midtones and highlights separately — the core tool of film color grading.")
        d["layer.posterize"] = HelpEntry(
            title: "Posterize",
            what: "Reduces the number of tones so the image breaks into flat blocks of color, like a poster or pop art.")
        d["layer.threshold"] = HelpEntry(
            title: "Threshold",
            what: "Turns the photo into pure black and pure white, like a woodcut or silhouette.")
        d["layer.invert"] = HelpEntry(
            title: "Invert",
            what: "Black becomes white and every color becomes its complement, like a film negative.")
        d["layer.lut"] = HelpEntry(
            title: "Color lookup (LUT)",
            what: "Load a ready-made grade (.cube file) and apply that look in one step. It can sit on top of other adjustments.")
        d["layer.brightnessContrast"] = HelpEntry(
            title: "Brightness/Contrast",
            what: "The simplest tone adjustment: two sliders for overall brightness and contrast.")
        d["layer.exposure"] = HelpEntry(
            title: "Exposure",
            what: "Adjusts exposure in stops like a camera, with Offset and Gamma as helpers.")
        d["layer.vibrance"] = HelpEntry(
            title: "Vibrance",
            what: "Adds color intelligently: only to muted colors, while protecting skin.")
        d["layer.shadowsHighlights"] = HelpEntry(
            title: "Shadows/Highlights",
            what: "Lifts dark areas and tames bright ones separately, while keeping local contrast. A lifesaver for backlit photos.")
        d["layer.hdrToning"] = HelpEntry(
            title: "HDR toning",
            what: "Strengthens local tone and detail for a bold, high-dynamic-range look.")
        d["layer.desaturate"] = HelpEntry(
            title: "Desaturate",
            what: "Turns the photo grayscale in one step.")
        d["layer.matchColor"] = HelpEntry(
            title: "Match color",
            what: "Pick a reference photo and this photo's overall color and tone shift toward it. Handy for making a set of photos consistent.")
        d["layer.replaceColor"] = HelpEntry(
            title: "Replace color",
            what: "Sample one color from the photo and change only that color's hue, saturation and lightness.")
        d["layer.equalize"] = HelpEntry(
            title: "Equalize",
            what: "Redistributes brightness automatically so dull photos gain separation.")

        // MARK: Curves
        d["curves.editor"] = HelpEntry(
            title: "Using curves",
            what: "Click the line to add a point, then drag it. The left side controls shadows, the middle midtones, the right highlights.",
            up: "Drag a point up: that brightness range gets brighter (in a red/green/blue channel, it adds that color).",
            down: "Drag a point down: that range gets darker (in a single channel, it adds the opposite color — down in red means more cyan).",
            tip: "Drag a point out of the box to delete it. Fewer points make smoother, more natural curves.")

        // MARK: Levels
        d["levels.inBlack"] = HelpEntry(
            title: "Input black",
            what: "Everything darker than this becomes pure black.",
            up: "Deeper shadows and more contrast — gray photos clear up.",
            down: "Back to the original.")
        d["levels.gamma"] = HelpEntry(
            title: "Midtones (gamma)",
            what: "Changes only the middle brightness; pure black and white stay put.",
            up: "Brighter midtones — lighter, with more shadow detail.",
            down: "Darker midtones — denser and moodier.")
        d["levels.inWhite"] = HelpEntry(
            title: "Input white",
            what: "Everything brighter than this becomes pure white.",
            up: "Back to the original.",
            down: "Brighter, cleaner highlights — but watch for blowouts.")
        d["levels.outBlack"] = HelpEntry(
            title: "Output black",
            what: "How dark the darkest point is allowed to be.",
            up: "Black turns gray — a faded, vintage look.",
            down: "Keeps true black.")
        d["levels.outWhite"] = HelpEntry(
            title: "Output white",
            what: "How bright the brightest point is allowed to be.",
            up: "Keeps true white.",
            down: "White turns gray — soft and dim like an old print.")
        d["levels.auto"] = HelpEntry(
            title: "Auto",
            what: "Uses the histogram to pull the darkest and brightest points to the ends — one click to clear up a gray photo.")
        d["levels.handles"] = HelpEntry(
            title: "Levels handles",
            what: "Under the histogram are three triangles: black is the black point, gray the midtones, white the white point. Drag them directly.",
            tip: "Drag the black and white triangles to where the histogram's hill starts and ends, and the photo clears up.")

        // MARK: Hue / Saturation
        d["hs.hue"] = HelpEntry(
            title: "Hue",
            what: "Rotates every color around the color wheel together.",
            up: "Colors shift one way: red → yellow → green…",
            down: "The other way: red → magenta → blue…",
            tip: "Big moves look surreal; small moves fine-tune the overall cast.")
        d["hs.saturation"] = HelpEntry(
            title: "Saturation",
            what: "Strength of all colors.",
            up: "Brighter, livelier colors.",
            down: "Paler; all the way left is black and white.")
        d["hs.lightness"] = HelpEntry(
            title: "Lightness",
            what: "Mixes the image toward white or black. Unlike exposure, colors fade as well.",
            up: "Like a white veil — lighter, paler, lower contrast.",
            down: "Like a black veil — darker, heavier colors.")
        d["hs.colorize"] = HelpEntry(
            title: "Colorize",
            what: "Turns the whole photo into a single-color tone, like sepia prints or a cold blue.")
        d["hs.colorizeHue"] = HelpEntry(
            title: "Colorize hue",
            what: "Which color the single tone uses.",
            tip: "Around 30 is nostalgic sepia; 200–220 is a cold blue.")
        d["hs.colorizeSat"] = HelpEntry(
            title: "Colorize saturation",
            what: "How strong the single tone is.",
            up: "Stronger color and style.",
            down: "Paler, close to black and white with a hint of tone.")

        // MARK: HSL
        d["hsl.hue"] = HelpEntry(
            title: "Hue (per color)",
            what: "Shifts only one color — for example, greens toward yellow or toward teal.",
            up: "Toward the next color on the wheel (red → orange, green → aqua, blue → purple).",
            down: "Toward the previous color (orange → red, green → yellow, blue → aqua).",
            tip: "A common Japanese-style move: greens right toward aqua, then lower their saturation.")
        d["hsl.saturation"] = HelpEntry(
            title: "Saturation (per color)",
            what: "Strength of one color only.",
            up: "That color becomes more vivid and eye-catching.",
            down: "That color fades and stops stealing attention.",
            tip: "If skin looks too red, lower Red and Orange saturation a little.")
        d["hsl.luminance"] = HelpEntry(
            title: "Luminance (per color)",
            what: "Brightness of one color only.",
            up: "That color gets lighter — skin looks fairer, for example.",
            down: "That color gets deeper — a blue sky becomes richer.")

        // MARK: Color balance
        d["cb.tone"] = HelpEntry(
            title: "Tone range",
            what: "Choose whether you're coloring the shadows, midtones or highlights.")
        d["cb.cyanRed"] = HelpEntry(
            title: "Cyan ↔ Red",
            what: "Shifts between cyan and red.",
            up: "Redder — warm and passionate.",
            down: "More cyan — cool and cinematic.")
        d["cb.magentaGreen"] = HelpEntry(
            title: "Magenta ↔ Green",
            what: "Shifts between magenta and green.",
            up: "Greener — fresh and natural; too much looks sickly.",
            down: "More magenta — romantic and dreamy.")
        d["cb.yellowBlue"] = HelpEntry(
            title: "Yellow ↔ Blue",
            what: "Shifts between yellow and blue.",
            up: "Bluer — calm, night-like.",
            down: "More yellow — nostalgic and sunny.")
        d["cb.preserve"] = HelpEntry(
            title: "Preserve luminosity",
            what: "When on, only color changes — adding color won't make the image brighter or darker.")

        // MARK: Selective color
        d["sc.group"] = HelpEntry(
            title: "Color family",
            what: "Choose which family of colors to change. Whites, Neutrals and Blacks cover the highlights, mid-grays and shadows.")
        d["sc.cyan"] = HelpEntry(
            title: "Cyan",
            what: "Adds or removes cyan ink in the chosen color.",
            up: "More cyan, less red.",
            down: "More red.")
        d["sc.magenta"] = HelpEntry(
            title: "Magenta",
            what: "Adds or removes magenta ink in the chosen color.",
            up: "More magenta, less green.",
            down: "More green.")
        d["sc.yellow"] = HelpEntry(
            title: "Yellow",
            what: "Adds or removes yellow ink in the chosen color.",
            up: "More yellow, less blue.",
            down: "More blue.")
        d["sc.black"] = HelpEntry(
            title: "Black",
            what: "Adds or removes black ink in the chosen color.",
            up: "That color gets deeper, darker, more solid.",
            down: "That color gets lighter, brighter, more transparent.")
        d["sc.mode"] = HelpEntry(
            title: "Relative / Absolute",
            what: "Relative scales the ink already there, so changes are gentler. Absolute adds or removes a fixed amount, so changes are stronger.")

        // MARK: Channel mixer
        d["cm.output"] = HelpEntry(
            title: "Output channel",
            what: "Choose which channel you're rebuilding: red, green or blue.")
        d["cm.red"] = HelpEntry(
            title: "Red source",
            what: "How much of the original red channel goes into this output channel.",
            up: "Areas that were red get brighter in this channel.",
            down: "Areas that were red get darker in this channel.")
        d["cm.green"] = HelpEntry(
            title: "Green source",
            what: "How much of the original green channel goes into this output channel.",
            up: "Areas that were green get brighter in this channel.",
            down: "Areas that were green get darker in this channel.")
        d["cm.blue"] = HelpEntry(
            title: "Blue source",
            what: "How much of the original blue channel goes into this output channel.",
            up: "Areas that were blue get brighter in this channel.",
            down: "Areas that were blue get darker in this channel.")
        d["cm.constant"] = HelpEntry(
            title: "Constant",
            what: "Adds a fixed amount to this channel everywhere.",
            up: "The whole image gets more of this channel's color (red constant up → warmer red cast).",
            down: "The whole image loses this color (red constant down → cyan cast).")
        d["cm.mono"] = HelpEntry(
            title: "Monochrome",
            what: "Outputs black and white, using the channel mix to decide how each tone renders.",
            tip: "Keep the three numbers adding up to about 100% to match the original brightness.")

        // MARK: Black & white
        let bw = [("bw.red", "Reds"), ("bw.yellow", "Yellows"), ("bw.green", "Greens"),
                  ("bw.cyan", "Cyans"), ("bw.blue", "Blues"), ("bw.magenta", "Magentas")]
        for (key, name) in bw {
            d[key] = HelpEntry(
                title: name,
                what: "How bright things that were \(name.lowercased()) become in the black-and-white image.",
                up: "\(name) turn lighter and whiter.",
                down: "\(name) turn darker and blacker.")
        }
        d["bw.blue"]?.tip = "Pull Blues left and the sky goes dark with standout clouds — the classic dramatic black and white."
        d["bw.red"]?.tip = "For portraits, push Reds right for clearer, brighter skin."
        d["bw.tint"] = HelpEntry(
            title: "Tint",
            what: "Washes the black and white with a color, like an old sepia print.")
        d["bw.tintHue"] = HelpEntry(
            title: "Tint hue",
            what: "Which color to tint with. Around 30 is sepia, around 210 a cold blue.")
        d["bw.tintSat"] = HelpEntry(
            title: "Tint saturation",
            what: "How strong the tint is.",
            up: "More visible color.",
            down: "Closer to pure black and white.")

        // MARK: Photo filter
        d["pf.color"] = HelpEntry(
            title: "Filter color",
            what: "The color of the filter in front of the lens. Warm colors warm the image; cool colors calm it.")
        d["pf.density"] = HelpEntry(
            title: "Density",
            what: "How deep the filter color is.",
            up: "Stronger tint — the whole image takes on the color.",
            down: "Just a hint of tone.")
        d["pf.preserve"] = HelpEntry(
            title: "Preserve luminosity",
            what: "When on, the filter won't darken the image. When off, it behaves like real glass in front of the lens and darkens slightly.")

        // MARK: Gradient map
        d["gm.stops"] = HelpEntry(
            title: "Color stops",
            what: "Each color point on the gradient. The left color goes to the darkest parts of the photo, the right color to the brightest.",
            tip: "Deep blue shadows with warm yellow highlights is the classic movie-poster duotone.")
        d["gm.position"] = HelpEntry(
            title: "Position",
            what: "Which brightness this color is placed at.",
            up: "Moves it toward the highlights.",
            down: "Moves it toward the shadows.")
        d["gm.reverse"] = HelpEntry(
            title: "Reverse",
            what: "Flips the gradient, swapping the shadow and highlight colors.")

        // MARK: Color grading
        d["cg.wheel"] = HelpEntry(
            title: "Color wheel",
            what: "Drag the dot: its direction chooses the color, its distance from the center sets how strong it is. Double-click the wheel to reset.",
            tip: "A common film look: shadows a little toward teal, highlights a little toward orange.")
        d["cg.hue"] = HelpEntry(
            title: "Hue",
            what: "Which color to add to this tone range — the same as the direction on the wheel.")
        d["cg.saturation"] = HelpEntry(
            title: "Strength",
            what: "How strong the added color is.",
            up: "More visible, bolder style.",
            down: "More subtle.")
        d["cg.luminance"] = HelpEntry(
            title: "Luminance",
            what: "Brightens or darkens this tone range.",
            up: "This range gets brighter.",
            down: "This range gets darker.")
        d["cg.blending"] = HelpEntry(
            title: "Blending",
            what: "How wide the transitions between shadows, midtones and highlights are.",
            up: "Softer transitions; the three colors blend together.",
            down: "Sharper boundaries; the three colors stay distinct.")
        d["cg.balance"] = HelpEntry(
            title: "Balance",
            what: "Moves the dividing line between shadows and highlights.",
            up: "The highlight color covers more of the image.",
            down: "The shadow color covers more of the image.")

        // MARK: Other
        d["poster.levels"] = HelpEntry(
            title: "Levels",
            what: "How many brightness steps each channel keeps.",
            up: "More steps — closer to the original.",
            down: "Fewer, bigger blocks — stronger poster and pop-art feel.")
        d["threshold.level"] = HelpEntry(
            title: "Threshold",
            what: "Anything darker than this becomes black, anything brighter becomes white.",
            up: "More black — heavier, darker image.",
            down: "More white — lighter, brighter image.")
        d["lut.intensity"] = HelpEntry(
            title: "Intensity",
            what: "How strongly the LUT is applied.",
            up: "The full LUT look.",
            down: "A lighter look, blended with the original.",
            tip: "Downloaded LUTs are often heavy; around 70% usually ages better.")

        // MARK: White balance picker & calibration
        d["wb.eyedropper"] = HelpEntry(
            title: "White balance picker",
            what: "Click something in the photo that should be white or gray (a white wall, a white shirt, gray pavement). Lumen works out the temperature and tint that make it neutral.",
            tip: "Don't click blown-out pure white — there's no color information left there.")
        d["calib.shadowTint"] = HelpEntry(
            title: "Shadow tint",
            what: "Adds a touch of green or magenta to the very darkest tones, to fix shadow casts some cameras produce.",
            up: "Shadows lean magenta — warmer and softer.",
            down: "Shadows lean green — a slightly cool, filmic feel.")
        d["calib.hue"] = HelpEntry(
            title: "Primary hue",
            what: "Changes how the camera reads this primary color. It affects every color that contains it, so it's broader and more fundamental than HSL.",
            up: "This primary shifts toward the next color on the wheel (red → orange, green → aqua, blue → purple).",
            down: "The other way (red → magenta, green → yellow, blue → aqua).",
            tip: "A secret of many film looks: blue primary hue left and saturation right — skin tones get clearer.")
        d["calib.saturation"] = HelpEntry(
            title: "Primary saturation",
            what: "Raises or lowers the purity of this primary color overall.",
            up: "Every color containing it gets richer.",
            down: "Every color containing it gets paler and quieter.")

        // MARK: Brightness/Contrast, Exposure
        d["bc.brightness"] = HelpEntry(
            title: "Brightness",
            what: "Overall lighter or darker, mostly in the midtones. The brightest and darkest points barely move.",
            up: "Brighter and lighter.",
            down: "Darker and steadier.")
        d["bc.contrast"] = HelpEntry(
            title: "Contrast",
            what: "The gap between light and dark.",
            up: "Harder, more impact.",
            down: "Softer, flatter.")
        d["exp.exposure"] = HelpEntry(
            title: "Exposure",
            what: "Adjusts brightness in stops in linear light, like a camera. The brightest areas change the most.",
            up: "Brighter overall; highlights blow out more easily.",
            down: "Darker overall.")
        d["exp.offset"] = HelpEntry(
            title: "Offset",
            what: "Adds or subtracts a fixed amount from every pixel, mostly affecting shadows.",
            up: "Shadows lift — the image gets gray and hazy.",
            down: "Shadows sink — heavier blacks.")
        d["exp.gamma"] = HelpEntry(
            title: "Gamma correction",
            what: "Bends the middle of the tone curve; pure black and white stay put.",
            up: "Brighter midtones.",
            down: "Darker, denser midtones.")

        // MARK: Shadows/Highlights
        d["sh.shadowsAmount"] = HelpEntry(
            title: "Shadow amount",
            what: "How much the dark areas are lifted.",
            up: "More shadow detail — flatter and more open.",
            down: "Shadows stay as they are.")
        d["sh.highlightsAmount"] = HelpEntry(
            title: "Highlight amount",
            what: "How much the bright areas are pulled down.",
            up: "Skies and bright surfaces regain their detail.",
            down: "Highlights stay as they are.")
        d["sh.radius"] = HelpEntry(
            title: "Radius",
            what: "How large an area is looked at to decide whether something counts as bright or dark.",
            up: "More natural, global transitions, but less local contrast.",
            down: "Finer control, but halos may appear along edges.")
        d["sh.colorCorrection"] = HelpEntry(
            title: "Color correction",
            what: "Lifting or darkening areas can make their color paler or stronger; this compensates.",
            up: "Adjusted areas get richer color.",
            down: "Adjusted areas get paler.")
        d["sh.midtoneContrast"] = HelpEntry(
            title: "Midtone contrast",
            what: "Lifting shadows can flatten the image; this brings midtone punch back.",
            up: "More dimensional.",
            down: "Softer.")

        // MARK: HDR toning
        d["hdr.radius"] = HelpEntry(
            title: "Edge glow radius",
            what: "How wide the local enhancement reaches.",
            up: "Large-scale light and dark contrast — dramatic, with halos along edges.",
            down: "Only small-scale detail is enhanced.")
        d["hdr.strength"] = HelpEntry(
            title: "Edge glow strength",
            what: "How hard local contrast is pushed.",
            up: "A stronger, more exaggerated HDR feel.",
            down: "More subtle and realistic.")
        d["hdr.gamma"] = HelpEntry(
            title: "Gamma",
            what: "Overall distribution of light and dark.",
            up: "Brighter midtones, lighter image.",
            down: "Darker midtones, heavier image.")
        d["hdr.exposure"] = HelpEntry(
            title: "Exposure",
            what: "Overall brightness in stops.",
            up: "Brighter.",
            down: "Darker.")
        d["hdr.detail"] = HelpEntry(
            title: "Detail",
            what: "How sharp the fine textures are.",
            up: "Very crisp, gritty texture with a strong HDR feel.",
            down: "Softer texture.")

        // MARK: Match color
        d["mc.luminance"] = HelpEntry(
            title: "Luminance",
            what: "Overall brightness after matching.",
            up: "Brighter.",
            down: "Darker.")
        d["mc.intensity"] = HelpEntry(
            title: "Color intensity",
            what: "Color strength after matching.",
            up: "Richer colors.",
            down: "Paler colors; all the way left is nearly grayscale.")
        d["mc.fade"] = HelpEntry(
            title: "Fade",
            what: "Blends the matched result back with the original.",
            up: "Closer and closer to the original.",
            down: "Fully matched.")
        d["mc.neutralize"] = HelpEntry(
            title: "Neutralize",
            what: "Removes the reference photo's own color cast, borrowing only its tone and color separation.")

        // MARK: Replace color
        d["rc.fuzziness"] = HelpEntry(
            title: "Fuzziness",
            what: "How close a color must be to the target to be replaced.",
            up: "A wider range — similar colors get replaced too.",
            down: "A narrower range — only very close colors.",
            tip: "First swing Hue to an extreme to see exactly what's selected, then tune Fuzziness.")
        d["rc.hue"] = HelpEntry(
            title: "Replacement hue",
            what: "Moves the selected color to another spot on the color wheel.",
            up: "Shifts color one way.",
            down: "Shifts color the other way.")
        d["rc.saturation"] = HelpEntry(
            title: "Replacement saturation",
            what: "Strength of the selected color.",
            up: "More vivid.",
            down: "Paler.")
        d["rc.lightness"] = HelpEntry(
            title: "Replacement lightness",
            what: "Brightness of the selected color.",
            up: "Lighter.",
            down: "Darker.")

        d["eq.recompute"] = HelpEntry(
            title: "Recalculate",
            what: "Equalize is measured from the image at the moment the layer was added. If you've changed the adjustments below it since, click here to measure again.")

        return d
    }()
}
