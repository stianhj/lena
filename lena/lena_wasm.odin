#+build js
package lena

import "core:fmt"
import "core:sys/wasm/js"

WASM_CANVAS     :: "lena-canvas"
WASM_BACKGROUND :: "lena-background"

play_sound :: proc(blob: []byte, volume: f64 = 1, loop := false, group: u8 = 0) -> bool {
	the_volume := max(volume, 0)
	the_group  := min(group, 15)
	blob       := blob

	ctx.group_volumes[the_group] = 1
	ctx.group_fader[the_group]   = 0

	wasm_update_volumes(raw_data(ctx.group_volumes[:]), len(ctx.group_volumes) * 8)
	wasm_play_sound(raw_data(blob), len(blob), the_volume, loop, the_group)
	return true // limitation: this may not actually be true, but we can't easily tell
}

clear_sounds :: proc(group: u8 = 0, with_fade: f64 = 0) {
	the_fade  := max(with_fade, 0)
	the_group := min(group, 15)

	if the_fade > 0 {
		if the_group > 0 {
			ctx.group_fader[the_group] = the_fade
			return
		}

		for &fader in ctx.group_fader {
			fader = the_fade
		}
		return
	}

	wasm_stop_sounds(group)
}

@export // called by lena.js
lena_wasm_step :: proc(delta_time: f64) {
	ctx.delta_time = delta_time
	step() // we call the full Lena step here
}

foreign import "lena_env"
@(default_calling_convention = "contextless", private)
foreign lena_env {
	wasm_set_canvas_size :: proc(w, h: int) ---
	wasm_write_canvas    :: proc(pointer: rawptr, len: int) ---
	wasm_play_sound      :: proc(pointer: rawptr, len: int, volume: f64, loop: bool, group: u8) ---
	wasm_update_volumes  :: proc(pointer: rawptr, len: int) ---
	wasm_stop_sounds     :: proc(group: u8) ---
}

@private
Platform_Context :: struct {
	last_window_background: u8,
	last_window_size:       [2]f64,
}

@private
Audio_Context :: struct {
	group_volumes: [16]f64,
	group_fader:   [16]f64,
}

@private
os_init :: proc(title: string) {
	ctx.window.w = ctx.screen.w
	ctx.window.h = ctx.screen.h

	wasm_set_canvas_size(ctx.screen.w, ctx.screen.h)

	js.add_event_listener(WASM_BACKGROUND, .Key_Down, nil, proc(e: js.Event) {
		code := switch_keys(e)
		ctx.key_state[code] = KEY_STATE_HELD | KEY_STATE_PRESSED
	})

	js.add_event_listener(WASM_BACKGROUND, .Key_Up, nil, proc(e: js.Event) {
		code := switch_keys(e)
		ctx.key_state[code] &= ~KEY_STATE_HELD
		ctx.key_state[code] |=  KEY_STATE_RELEASED
	})

	js.add_event_listener(WASM_BACKGROUND, .Pointer_Down, nil, proc(e: js.Event) {
		button := switch_button(e.mouse.button)
		ctx.mouse_state[button] = KEY_STATE_HELD | KEY_STATE_PRESSED
	}, true)

	js.add_event_listener(WASM_BACKGROUND, .Pointer_Up, nil, proc(e: js.Event) {
		button := switch_button(e.mouse.button)
		ctx.mouse_state[button] &= ~KEY_STATE_HELD
		ctx.mouse_state[button] |= KEY_STATE_RELEASED
	}, true)

	js.add_event_listener(WASM_BACKGROUND, .Mouse_Move, nil, proc(e: js.Event) {
		rect := js.get_bounding_client_rect(WASM_CANVAS)
		x, y := cast(f64) e.mouse.client.x, cast(f64) e.mouse.client.y
		w, h := cast(f64) ctx.screen.w,     cast(f64) ctx.screen.h
		ctx.mouse_pos.x = cast(int) ((x - rect.x) / rect.width  * w)
		ctx.mouse_pos.y = cast(int) ((y - rect.y) / rect.height * h)
	})

	js.add_event_listener(WASM_BACKGROUND, .Focus_In,  nil, proc(e: js.Event) {
		ctx.has_focus = true
	})

	js.add_event_listener(WASM_BACKGROUND, .Focus_Out, nil, proc(e: js.Event) {
		ctx.has_focus = false
	})

	js.add_event_listener(WASM_BACKGROUND, .Unload, nil, proc(e: js.Event) {
		ctx.set_quit = true
	})

	os_update_cursor()
}

@private
audio_init :: proc() {
	for &group in ctx.group_volumes {
		group = 1
	}
}

@private
os_modify_palette :: proc() {
	for &c in ctx.palette {
		c = transmute(u32) (transmute([4]u8) c).bgra
	}
}

@private
os_step :: proc() {
	rect := js.get_bounding_client_rect(WASM_BACKGROUND)
	if rect.width != ctx.last_window_size.x || rect.height != ctx.last_window_size.y {
		none, wide := "auto", "100%"

		if rect.width < rect.height {
			none, wide = wide, none
		}

		js.set_element_style(WASM_CANVAS, "width",  none)
		js.set_element_style(WASM_CANVAS, "height", wide)

		ctx.last_window_size.x = rect.width
		ctx.last_window_size.y = rect.height
	}
}

@private
audio_step :: proc(delta_time: f64) {
	needs_update := false

	for &group, index in ctx.group_volumes {
		fader := ctx.group_fader[index]
		if fader > 0 {
			group -= ctx.delta_time / fader
			needs_update = true

			if group < 0 {
				group = 0
				ctx.group_fader[index] = 0
				clear_sounds(group = cast(u8) index)
			}
		}
	}

	if needs_update {
		wasm_update_volumes(raw_data(ctx.group_volumes[:]), len(ctx.group_volumes) * 8)
	}
}

@private
os_present :: proc() {
	if ctx.last_window_background != ctx.window_background {
		ctx.last_window_background = ctx.window_background
		color := transmute(u32) (transmute([4]u8) ctx.palette[ctx.window_background]).abgr
		color_string := fmt.tprintf("#%X", color)
		js.set_element_style(WASM_BACKGROUND, "background-color", color_string)
	}

	wasm_write_canvas(raw_data(ctx.backbuffer), len(ctx.backbuffer) * 4)
}

@private
os_update_cursor :: proc() {
	mode := "none" if .HIDE_CURSOR in ctx.flags else "auto"
	js.set_element_style(WASM_BACKGROUND, "cursor", mode)
}

@private
switch_button :: proc(x: i16) -> Mouse {
	switch x {
	case 1: return .MIDDLE
	case 2: return .RIGHT
	}
	return .LEFT
}

@private
switch_keys :: proc(e: js.Event) -> Key {
	switch e.key.key {
	case "0":
		#partial switch e.key.location {
		case .Standard: return .N0
		case .Numpad:   return .P0
		}
	case "1":
		#partial switch e.key.location {
		case .Standard: return .N1
		case .Numpad:   return .P1
		}
	case "2":
		#partial switch e.key.location {
		case .Standard: return .N2
		case .Numpad:   return .P2
		}
	case "3":
		#partial switch e.key.location {
		case .Standard: return .N3
		case .Numpad:   return .P3
		}
	case "4":
		#partial switch e.key.location {
		case .Standard: return .N4
		case .Numpad:   return .P4
		}
	case "5":
		#partial switch e.key.location {
		case .Standard: return .N5
		case .Numpad:   return .P5
		}
	case "6":
		#partial switch e.key.location {
		case .Standard: return .N6
		case .Numpad:   return .P6
		}
	case "7":
		#partial switch e.key.location {
		case .Standard: return .N7
		case .Numpad:   return .P7
		}
	case "8":
		#partial switch e.key.location {
		case .Standard: return .N8
		case .Numpad:   return .P8
		}
	case "9":
		#partial switch e.key.location {
		case .Standard: return .N9
		case .Numpad:   return .P9
		}

	case "A", "a": return .A
	case "B", "b": return .B
	case "C", "c": return .C
	case "D", "d": return .D
	case "E", "e": return .E
	case "F", "f": return .F
	case "G", "g": return .G
	case "H", "h": return .H
	case "I", "i": return .I
	case "J", "j": return .J
	case "K", "k": return .K
	case "L", "l": return .L
	case "M", "m": return .M
	case "N", "n": return .N
	case "O", "o": return .O
	case "P", "p": return .P
	case "Q", "q": return .Q
	case "R", "r": return .R
	case "S", "s": return .S
	case "T", "t": return .T
	case "U", "u": return .U
	case "V", "v": return .V
	case "W", "w": return .W
	case "X", "x": return .X
	case "Y", "y": return .Y
	case "Z", "z": return .Z

	case "Tab":        return .TAB
	case "Backspace":  return .BACKSPACE
	case "Delete":     return .DELETE
	case "Escape":     return .ESCAPE
	case "Space", " ": return .SPACE

	case "Shift":
		#partial switch e.key.location {
		case .Left:  return .LEFT_SHIFT
		case .Right: return .RIGHT_SHIFT
		}

	case "Control":
		#partial switch e.key.location {
		case .Left:  return .LEFT_CONTROL
		case .Right: return .RIGHT_CONTROL
		}
	case "Alt":
		#partial switch e.key.location {
		case .Left:  return .LEFT_ALT
		case .Right: return .RIGHT_ALT
		}
	case "Meta":
		#partial switch e.key.location {
		case .Left:  return .LEFT_SUPER
		case .Right: return .RIGHT_SUPER
		}

	case "End":        return .END
	case "Home":       return .HOME
	case "ArrowLeft":  return .LEFT
	case "ArrowUp":    return .UP
	case "ArrowRight": return .RIGHT
	case "ArrowDown":  return .DOWN

	case "Enter":
		#partial switch e.key.location {
		case .Standard:  return .RETURN
		case .Numpad:    return .KEYPAD_RETURN
		}

	case "=":
		#partial switch e.key.location {
		case .Standard:  return .EQUALS
		case .Numpad:    return .KEYPAD_EQUALS
		}

	case ".":
		#partial switch e.key.location {
		case .Standard:  return .DOT
		case .Numpad:    return .KEYPAD_DOT
		}

	case "-":
		#partial switch e.key.location {
		case .Standard:  return .MINUS
		case .Numpad:    return .KEYPAD_MINUS
		}

	case "/":
		#partial switch e.key.location {
		case .Standard:  return .SLASH
		case .Numpad:    return .KEYPAD_DIVIDE
		}

	case ";": return .SEMICOLON
	case ",": return .COMMA
	case "`": return .GRAVE
	case "+": return .KEYPAD_PLUS
	case "*": return .KEYPAD_MULTIPLY

	case "PageUp":   return .PAGE_UP
	case "PageDown": return .PAGE_DOWN

	case "[":  return .LEFT_BRACKET
	case "]":  return .RIGHT_BRACKET
	case "\\": return .BACKSLASH
	case "'":  return .QUOTE

	case "F1":  return .F1
	case "F2":  return .F2
	case "F3":  return .F3
	case "F4":  return .F4
	case "F5":  return .F5
	case "F6":  return .F6
	case "F7":  return .F7
	case "F8":  return .F8
	case "F9":  return .F9
	case "F10": return .F10
	case "F11": return .F11
	case "F12": return .F12
	case "F13": return .F13
	case "F14": return .F14
	case "F15": return .F15
	case "F16": return .F16
	case "F17": return .F17
	case "F18": return .F18
	case "F19": return .F19
	case "F20": return .F20
	}

	return .UNKNOWN
}

// unused
@private os_set_title         :: proc(title: string) {}
@private os_show_window       :: proc() {}
@private os_update_fullscreen :: proc() {}
@private os_destroy           :: proc() {}
@private audio_destroy        :: proc() {}
