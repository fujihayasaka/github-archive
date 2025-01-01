export default `

uniform bool uIsEye;
uniform float uWink;
varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vViewPosition;
varying vec3 vLocalPosition;

float parabola(float x){
	return -pow(2.0 * x, 2.0);
}

void main() {
	vUv = uv;
	vec3 objectNormal = vec3( normal );
	vec3 transformedNormal = objectNormal;
	transformedNormal = normalMatrix * transformedNormal;
	vNormal = normalize( transformedNormal );

	vec3 transformed = vec3( position );
	vLocalPosition = transformed;

	vec4 worldPosition = modelMatrix * vec4(transformed, 1.0);
	vViewPosition.y = worldPosition.y;

	transformed.y += parabola(transformed.x) * uWink * 2.0;

	vec4 mvPosition = vec4( transformed, 1.0 );
	mvPosition = modelViewMatrix * mvPosition;
	vViewPosition = - mvPosition.xyz;
	gl_Position = projectionMatrix * mvPosition;
}
`
