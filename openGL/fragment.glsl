precision highp float;

uniform vec2 resolution;
uniform float elapsedTime, waveScale, bandDensity, foldAmount, glossiness;
uniform float purpleAmount, creaseDepth, waveGap, fogAmount, qualitySteps;
uniform float colorShiftEnabled, colorShiftTime;

const float RIBBON_HEIGHT_SCALE = .3;
const float PI = 3.14159265;

float hash(vec2 coordinate) {
  coordinate = fract(coordinate * vec2(123.34, 456.21));
  coordinate += dot(coordinate, coordinate + 45.32);
  return fract(coordinate.x * coordinate.y);
}

float noise(vec2 point) {
  vec2 cell = floor(point), fractionalPosition = fract(point);
  fractionalPosition = fractionalPosition * fractionalPosition * fractionalPosition
    * (fractionalPosition * (fractionalPosition * 6. - 15.) + 10.);
  return mix(
    mix(hash(cell), hash(cell + vec2(1, 0)), fractionalPosition.x),
    mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1, 1)), fractionalPosition.x),
    fractionalPosition.y
  );
}

float fbm(vec2 point) {
  float noiseValue = 0., amplitude = .55;
  mat2 rotationMatrix = mat2(1.5, 1.1, -1.1, 1.5);

  for (int octaveIndex = 0; octaveIndex < 2; octaveIndex++) {
    noiseValue += amplitude * noise(point);
    point = rotationMatrix * point;
    amplitude *= .45;
  }

  return noiseValue;
}

float phase(vec2 point, float ribbonId) {
  float rotationAngle = -.1 + .35 * sin(ribbonId * 2.3 + 1.);
  vec2 rotatedPoint = mat2(cos(rotationAngle), -sin(rotationAngle),
    sin(rotationAngle), cos(rotationAngle)) * point;
  float seed = ribbonId * 7.3;

  float phaseValue = rotatedPoint.y * bandDensity
    * (1. + .12 * sin(ribbonId * 1.7)) + rotatedPoint.x * .3;

  phaseValue += 1.6 * sin(rotatedPoint.x * .9 + elapsedTime * .35
    + rotatedPoint.y * .6 + seed);
  phaseValue += 1.1 * sin(rotatedPoint.x * 1.7 - rotatedPoint.y * 1.3
    - elapsedTime * .28 + seed * 2.);
  phaseValue += foldAmount * 4.6 * fbm(
    rotatedPoint * .72 + seed + vec2(elapsedTime * .06, -elapsedTime * .05)
  );
  phaseValue += elapsedTime * .12 * (mod(ribbonId, 2.) < .5 ? 1. : -.7);

  return phaseValue;
}

float ribbonHeight(vec2 point, float ribbonId, out float sweep) {
  float phaseValue = phase(point, ribbonId);
  float sweepPosition = fract(phaseValue) / (1. - .5 * waveGap);

  sweep = sweepPosition < 1. ? sin(PI * sweepPosition) : 0.;

  float profileHeight = sweep * (1.35 - .35 * sweep);

  return profileHeight * (.55 + .9 * hash(vec2(floor(phaseValue), ribbonId * 3.7)));
}

vec3 rotateHue(vec3 color, float angle) {
  vec3 rotationAxis = vec3(.57735);
  return color * cos(angle) + cross(rotationAxis, color) * sin(angle)
    + rotationAxis * dot(rotationAxis, color) * (1. - cos(angle));
}

const vec3 HAZE = vec3(.004, .01, .04);

vec4 shadeRibbon(
  vec2 screenPosition,
  float ribbonId,
  float rayDepth,
  vec2 screenUV,
  vec2 cameraOffset
) {
  float unusedSweep, surfaceSweep;
  float rayStartDepth = max(rayDepth - RIBBON_HEIGHT_SCALE * 1.45, .1);
  float depthStep = (rayDepth - rayStartDepth) / qualitySteps;
  float previousDepth = rayStartDepth, hitDepth = -1.;

  for (int stepIndex = 0; stepIndex < 32; stepIndex++) {
    if (float(stepIndex) >= qualitySteps) break;

    float sampleDepth = rayStartDepth + depthStep * (float(stepIndex) + 1.);
    vec2 samplePosition = (screenPosition * sampleDepth + cameraOffset)
      * 1.9 / waveScale;
    float sampledHeight = ribbonHeight(samplePosition, ribbonId, unusedSweep);

    if (sampleDepth >= rayDepth - RIBBON_HEIGHT_SCALE * sampledHeight
        && sampledHeight > .004) {
      hitDepth = sampleDepth;
      break;
    }

    previousDepth = sampleDepth;
  }

  if (hitDepth < 0.) return vec4(0.);

  float lowerDepth = previousDepth, upperDepth = hitDepth;

  for (int refinementStep = 0; refinementStep < 4; refinementStep++) {
    float midpointDepth = .5 * (lowerDepth + upperDepth);
    vec2 midpointPosition = (screenPosition * midpointDepth + cameraOffset)
      * 1.9 / waveScale;
    float midpointHeight = ribbonHeight(midpointPosition, ribbonId, unusedSweep);

    if (midpointDepth >= rayDepth - RIBBON_HEIGHT_SCALE * midpointHeight
        && midpointHeight > .004)
      upperDepth = midpointDepth;
    else
      lowerDepth = midpointDepth;
  }

  float surfaceDepth = upperDepth;
  vec2 surfacePosition = (screenPosition * surfaceDepth + cameraOffset)
    * 1.9 / waveScale;
  float surfaceHeight = ribbonHeight(surfacePosition, ribbonId, surfaceSweep);

  float normalOffset = .006;
  float normalScale = RIBBON_HEIGHT_SCALE * 1.9 / waveScale / normalOffset;

  float heightDeltaX = ribbonHeight(
    surfacePosition + vec2(normalOffset, 0.), ribbonId, unusedSweep
  ) - surfaceHeight;

  float heightDeltaY = ribbonHeight(
    surfacePosition + vec2(0., normalOffset), ribbonId, unusedSweep
  ) - surfaceHeight;

  vec3 surfaceNormal = normalize(vec3(
    -heightDeltaX * normalScale,
    -heightDeltaY * normalScale,
    -1.
  ));

  vec3 worldPosition = vec3(screenPosition * surfaceDepth, surfaceDepth);
  vec3 viewDirection = normalize(-worldPosition);
  vec3 lightDirection = normalize(vec3(-.4, .55, -.7));
  vec3 reflectionDirection = normalize(vec3(.7, -.4, -.3));

  float occlusion = 0.;

  for (int shadowSampleIndex = 0; shadowSampleIndex < 1; shadowSampleIndex++) {
    float shadowDistance = .25 + .4 * float(shadowSampleIndex);
    vec2 shadowSamplePosition = surfacePosition
      + lightDirection.xy * shadowDistance * 1.9 / waveScale;
    float shadowSampleHeight = RIBBON_HEIGHT_SCALE
      * ribbonHeight(shadowSamplePosition, ribbonId, unusedSweep);

    occlusion = max(
      occlusion,
      smoothstep(-.03, .12, shadowSampleHeight
        - (RIBBON_HEIGHT_SCALE * surfaceHeight
          + abs(lightDirection.z) * shadowDistance))
    );
  }

  float shadowAmount = 1. - .7 * occlusion;

  float diffuseLighting = clamp(dot(surfaceNormal, lightDirection), 0., 1.)
    * shadowAmount;
  float rimLighting = pow(clamp(dot(surfaceNormal, reflectionDirection), 0., 1.), 2.);
  float fresnel = pow(1. - clamp(dot(surfaceNormal, viewDirection), 0., 1.), 2.5);

  vec3 reflectedView = reflect(-viewDirection, surfaceNormal);
  vec3 halfVector = normalize(lightDirection + viewDirection);

  vec3 deep = vec3(.015, .03, .30);
  vec3 blue = vec3(.04, .28, 1.00);
  vec3 teal = vec3(.00, .80, .92);
  vec3 purple = vec3(.62, .24, 1.00);

  float lighting = clamp(.18 + .95 * diffuseLighting, 0., 1.);

  vec3 color = mix(deep, blue, smoothstep(.1, .5, lighting));
  color = mix(color, teal, smoothstep(.45, .95, lighting));

  float purpleBlend = smoothstep(
    .25, 1.05,
    screenUV.x * .95 + (1. - lighting) * .45 - .12
    + .15 * sin(surfacePosition.x * .5) + .04 * ribbonId
  );

  color = mix(color, purple * (.45 + .8 * lighting), purpleAmount * purpleBlend);

  vec3 environmentColor = mix(deep, teal, smoothstep(-.1, .7, -reflectedView.z));
  environmentColor = mix(
    environmentColor,
    purple,
    purpleAmount * .5 * smoothstep(-.2, .8, reflectedView.x)
  );

  color += glossiness * fresnel * environmentColor
    * .9 * (.4 + .6 * shadowAmount);

  color += glossiness * shadowAmount * (
    pow(clamp(dot(surfaceNormal, halfVector), 0., 1.), 18.) * .25 * teal
    + pow(clamp(dot(surfaceNormal, halfVector), 0., 1.), 140.) * vec3(.8, 1., 1.)
  );

  color += glossiness * rimLighting * .35
    * mix(teal, purple, purpleAmount * purpleBlend);

  color *= mix(1., smoothstep(.0, .35, surfaceSweep), .6 * creaseDepth);
  color *= .55 + .6 * shadowAmount;

  color = mix(
    color,
    rotateHue(color, colorShiftTime + screenUV.x * 1.6
      + screenUV.y * .8 + .15 * ribbonId),
    colorShiftEnabled
  );

  float fogFactor = 1. - exp(-fogAmount * .3 * (surfaceDepth - 1.));
  color = mix(color, HAZE * (.5 + .5 * lighting), fogFactor * .85);

  return vec4(color, smoothstep(.004, .1, surfaceHeight));
}

void main() {
  vec2 screenUV = gl_FragCoord.xy / resolution;
  vec2 screenPosition = (screenUV - .5)
    * vec2(resolution.x / resolution.y, 1.);
  vec2 cameraOffset = vec2(
    sin(elapsedTime * .17) * .6,
    sin(elapsedTime * .13) * .25
  );

  float rayDepth = RIBBON_HEIGHT_SCALE * 1.5 + .5;
  vec4 ribbon = shadeRibbon(screenPosition, 0., rayDepth, screenUV, cameraOffset);
  vec3 color = ribbon.rgb * ribbon.a;

  color *= 1. - .4 * dot(screenUV - .5, screenUV - .5) * 2.;
  color = 1. - exp(-color * 1.7);
  color = pow(color, vec3(.95));

  gl_FragColor = vec4(color, 1.);
}
