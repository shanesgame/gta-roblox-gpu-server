local Config = {}

Config.STAGE = Vector2.new(1280, 720)
Config.SLIDE_MS = 850
Config.CYCLE_MS = 14000
Config.PARALLAX_MS = 42000

Config.ORDERS = { {1, 17, 19, 4, 13, 3, 18, 11, 10, 9, 16, 7, 12, 15, 5, 8, 14}, {1, 5, 7, 18, 12, 17, 19, 8, 10, 16, 4, 15, 11, 14, 3, 9, 13}, {1, 8, 17, 15, 14, 4, 11, 3, 16, 19, 9, 10, 5, 18, 13, 7, 12}, {1, 9, 19, 10, 14, 5, 12, 15, 8, 18, 7, 13, 4, 17, 3, 16, 11}, {1, 12, 13, 8, 19, 15, 10, 14, 5, 3, 16, 12, 9, 17, 7, 4, 18}, {1, 11, 17, 3, 14, 18, 9, 10, 19, 4, 13, 7, 8, 5, 15, 16, 11} }

Config.SCREENS = {
	{
		{ tex = "beach_bg", w = 1024, h = 512, x = 98, y = 95, yr = 20, to = { yr = -6, xr = 5 } },
		{ tex = "beach_fg", w = 343, h = 629, x = 480, y = 95, yr = 0, to = { x = 720 } },
	},
	nil,
	{
		{ tex = "ls0_background", w = 1024, h = 512, x = 98, y = 95, yr = 7, to = {yr = -7} },
		{ tex = "ls0_foreground", w = 299, h = 599, x = 360, y = 140, yr = 7, to = { x = 560 } },
	},
	{
		{ tex = "ls1_background", w = 1024, h = 512, x = 98, y = 95, yr = 6, to = {yr = -12} },
		{ tex = "ls1_foreground", w = 503, h = 206, x = 300, y = 465, yr = 0, to = { x = 480 } },
		{ tex = "ls1_foreground_franklin", w = 368, h = 588, x = 440, y = 140, yr = 0, to = { x = 745 } },
	},
	{
		{ tex = "ls2_background", w = 1024, h = 512, x = 98, y = 95, yr = 7, to = {yr = -5, xr = 5} },
		{ tex = "ls2_foreground", w = 311, h = 558, x = 745, y = 200, yr = 0, to = { x = 450 } },
		{ tex = "ls2_foreground_chop", w = 320, h = 512, x = 640, y = 260, yr = 0, to = { x = 310 } },
	},
	{
		{ tex = "ls3_background", w = 1024, h = 512, x = 110, y = 95, yr = 12, to = {yr = -4} },
		{ tex = "ls3_foreground", w = 412, h = 609, x = 440, y = 120, yr = 0, to = { x = 730 } },
	},
	{
		{ tex = "ls4_background", w = 1024, h = 512, x = 98, y = 95, yr = 7, to = {yr = -4, xr = 5} },
		{ tex = "ls4_foreground", w = 251, h = 643, x = 400, y = 85, yr = 0, to = { x = 250 } },
	},
	{
		{ tex = "ls5_background", w = 1024, h = 512, x = 98, y = 95, yr = 7, to = {yr = -6} },
		{ tex = "ls5_foreground", w = 389, h = 640, x = 450, y = 95, yr = 0, to = { x = 700 } },
	},
	{
		{ tex = "ls6_background", w = 1024, h = 512, x = 98, y = 95, yr = 7, to = {yr = 0, xr = 5} },
		{ tex = "ls6_foreground", w = 367, h = 603, x = 410, y = 115, yr = 0, to = { x = 800 } },
	},
	{
		{ tex = "ls7_background", w = 1024, h = 512, x = 98, y = 95, yr = 6, to = {yr = -6, xr = 5} },
		{ tex = "ls7_foreground", w = 311, h = 625, x = 860, y = 95, yr = 0, to = { x = 520 } },
	},
	{
		{ tex = "ls8_background", w = 1024, h = 512, x = 98, y = 95, yr = 7, to = {yr = -5, xr = 5} },
		{ tex = "ls8_foreground", w = 492, h = 497, x = 400, y = 190, yr = 0, to = { x = 660 } },
	},
	{
		{ tex = "ls9_background", w = 1024, h = 512, x = 98, y = 95, yr = 7, to = {yr = -3, xr = 5} },
		{ tex = "ls9_foreground", w = 331, h = 675, x = 220, y = 50, yr = 0, to = { x = 140 } },
	},
	{
		{ tex = "ls10_background", w = 1024, h = 512, x = 98, y = 95, yr = 6, to = {yr = -5, xr = 5} },
		{ tex = "ls10_foreground", w = 352, h = 682, x = 545, y = 65, yr = 0, to = { x = 485 } },
	},
	{
		{ tex = "ls11_background", w = 1024, h = 512, x = 98, y = 95, yr = 7, to = {yr = -3, xr = 5} },
		{ tex = "ls11_foreground", w = 344, h = 669, x = 309, y = 51, yr = 0, to = { x = 424 } },
	},
	{
		{ tex = "ls12_background", w = 1024, h = 512, x = 98, y = 95, yr = 6, to = {yr = -4} },
		{ tex = "ls12_foreground_michael", w = 462, h = 677, x = 345, y = 42, yr = 0, to = { x = 220 } },
	},
	{
		{ tex = "ls13_background", w = 1024, h = 512, x = 98, y = 95, yr = 5, to = {yr = -6, xr = 5} },
		{ tex = "ls13_foreground", w = 399, h = 681, x = 430, y = 39, yr = 0, to = { x = 250 } },
	},
	{
		{ tex = "ls14_background", w = 1024, h = 512, x = 98, y = 95, yr = 6, to = {yr = -2, xr = 5} },
		{ tex = "ls14_foreground", w = 392, h = 631, x = 650, y = 95, yr = 0, to = { x = 850 } },
	},
	{
		{ tex = "ls15_background", w = 1024, h = 512, x = 98, y = 95, yr = 6, to = {yr = -3, xr = 5} },
		{ tex = "ls15_foreground", w = 385, h = 642, x = 404, y = 78, yr = 0, to = { x = 261 } },
	},
	{
		{ tex = "ls16_background", w = 1024, h = 512, x = 98, y = 95, yr = 6, to = {yr = -3, xr = 5} },
		{ tex = "ls16_foreground", w = 300, h = 600, x = 300, y = 150, yr = 0, to = { x = 400 } },
	},
}

return Config