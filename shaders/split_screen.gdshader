shader_type canvas_item;

// Split screen: each pixel shows the view whose site (the spot its players
// sit on screen) is nearest - a Voronoi split, so the cut always runs
// between players, square to the line joining them. A thin line marks it.

uniform sampler2D view0 : filter_linear;
uniform sampler2D view1 : filter_linear;
uniform sampler2D view2 : filter_linear;
uniform sampler2D view3 : filter_linear;
uniform vec2 sites[4];
uniform int count = 2;
uniform vec2 screen = vec2(1280.0, 720.0);
uniform float line = 1.0;          // 0..1, how strongly the split line shows
uniform float line_width = 3.0;    // px
uniform vec4 line_color : source_color = vec4(0.05, 0.04, 0.06, 1.0);

void fragment() {
	vec2 p = UV * screen;
	int a = 0;
	int b = 1;
	float da = 1e20;
	float db = 1e20;
	for (int i = 0; i < 4; i++) {
		if (i >= count) {
			break;
		}
		float d = dot(p - sites[i], p - sites[i]);
		if (d < da) {
			b = a;
			db = da;
			a = i;
			da = d;
		} else if (d < db) {
			b = i;
			db = d;
		}
	}
	vec4 c;
	if (a == 0) {
		c = texture(view0, UV);
	} else if (a == 1) {
		c = texture(view1, UV);
	} else if (a == 2) {
		c = texture(view2, UV);
	} else {
		c = texture(view3, UV);
	}
	// Distance to the cut between the nearest two sites.
	float gap = max(length(sites[a] - sites[b]), 1e-3);
	float edge = (db - da) / (2.0 * gap);
	float w = line_width * line;
	c.rgb = mix(c.rgb, line_color.rgb, line * (1.0 - smoothstep(w - 1.0, w + 1.0, edge)));
	COLOR = vec4(c.rgb, 1.0);
}
