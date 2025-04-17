# Lena WebAssembly

Lena also runs in the browser, but it requires some additional set up.  You'll need the contents of this directory to get an embedded game up and running.

- `lena.js`
- `index.html`

`lena.js` is a modified copy of the `odin.js` file that comes with Odin in `core:sys/wasm/js`, with some additional procedures and configuration that helps map Lena functionality to the browser.

The `index.html` file is a representative template; you can build whatever HTML you like or embed it in any kind of page.

> [!WARNING]
> The WASM backend is very, very likely to break; much more so than the other platform targets, due to the rapid evolution of the Odin compiler. This version is up-to-date and is expected to work — aside from bugs I didn't find — with Odin `2025-04`.

## Browser Rules

Lena's WASM audio relies on the browser's `AudioContext` API. Because of browser security and and autoplay restrictions, an `AudioContext` must be started via an end-user interaction.

The `index.html` file in this package assumes the game is being served from behind such an interaction, like Itch.io's 'Run Game' game button, which then loads the assets in an `iframe`. If this is not the case, you will need to place the `window.lena.start` call behind a similar interaction for the end-user. A basic example of this has been commented out in the HTML.

## Compiling for WASM with Odin

```bat
odin build main.odin -file -target:js_wasm32 -out:main.wasm
```

## Architecture Notes

A traditional Lena game would be structured as follows:

```odin
main :: proc() {
	lena.init(...)
	defer lena.destroy()

	// set up stuff here

	for delta_time in lena.step() {
		// do game loop stuff here
	}
}
```

While this is a much simpler code path, this isn't possible in WASM, because our game must be driven by the browser. In order to make a Lena game WASM-compatible, we must reorganise like so:

```odin
main :: proc() {
	lena.init(...)

	// set up stuff here
}

@export
step :: proc(delta_time: f64) -> bool {
	// do game loop stuff here

	if lena.still_running() {
		return true
	}

	lena.destroy()
	return false
}
```

We can then make the build cross-compatible with both desktop and browser targets by designing it WASM-first, with a `when` statement to re-enable standard functionality:

```odin
main :: proc() {
	lena.init(...)

	// set up stuff here

	when !lena.IS_WEB {
		for delta_time in lena.step() {
			step(delta_time)
		}
	}
}

@export
step :: proc(delta_time: f64) -> bool {
	// do game loop stuff here

	if lena.still_running() {
		return true
	}

	lena.destroy()
	return false
}
```
