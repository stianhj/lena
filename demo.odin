package demo

import "lena"

WHITE  :: 1
CYAN   :: 9
BLUE   :: 10
NAVY   :: 11
YELLOW :: 15
ORANGE :: 16

CLOVER :: #load("demo.png")

main :: proc() {
	lena.init("Hello, Lena!", 128, 128, flags = {.HIDE_WINDOW, .HIDE_CURSOR})
	defer lena.destroy()

	lena.set_window_background(BLUE)

	lena.set_text_color(WHITE)
	lena.set_bold_color(YELLOW)

	// if yellow is drawn over white, substitute orange
	// and don't let yellow on yellow disappear
	lena.set_blend_palette_pair(WHITE,  YELLOW, ORANGE)
	lena.set_blend_palette_pair(YELLOW, YELLOW, ORANGE)

	// if the cyan text is drawn over the navy background
	// or the yellow cursor, flip it to white and orange
	lena.set_blend_palette_pair(CYAN, NAVY,   WHITE)
	lena.set_blend_palette_pair(CYAN, YELLOW, ORANGE)

	// make a blank image to capture drawing
	canvas := lena.create_image(128, 128)
	defer lena.destroy_image(canvas)

	// convert our clover PNG into a Lena image
	clover := lena.create_image_from_png(CLOVER)
	defer lena.destroy_image(clover)

	lena.show_window()

	for _ in lena.step() {
		if lena.key_pressed(.F11) {
			lena.toggle_fullscreen()
		}

		if lena.key_pressed(.ESCAPE) {
			lena.quit()
		}

		mx, my := lena.get_cursor()

		lena.clear_screen(CYAN)

		if lena.mouse_held(.LEFT) {
			// draw paint to canvas
			lena.draw_circle_to_image(canvas, mx, my, 14, YELLOW, true)

			// copy clovers to canvas but clipped to canvas alpha
			lena.set_draw_state({.LOCK_ALPHA})
			lena.draw_image_to_image(clover, canvas, 0, 0)
		}

		// draw composited canvas to screen
		lena.set_draw_state({.BLEND})
		lena.draw_image(canvas, 0, 0)

		// draw yellow cursor
		lena.draw_circle(mx, my, 14, YELLOW, true)

		// draw both sets of text
		lena.set_text_color(WHITE)
		lena.draw_text("Welcome to |*Lena*!", 10, 54 - 47)

		lena.set_text_color(CYAN)
		lena.draw_text("Hold down |left click...", 10, 66 - 47)
	}
}
