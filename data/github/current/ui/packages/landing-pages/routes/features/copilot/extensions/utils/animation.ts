// Adapted from https://easings.net/

// Bezier curves
export const easeInSine = 'cubic-bezier(0.12, 0, 0.39, 0)'
export const easeOutSine = 'cubic-bezier(0.61, 1, 0.88, 1)'
export const easeInOutSine = 'cubic-bezier(0.37, 0, 0.63, 1)'
export const easeInQuad = 'cubic-bezier(0.11, 0, 0.5, 0)'
export const easeOutQuad = 'cubic-bezier(0.5, 1, 0.89, 1)'
export const easeInOutQuad = 'cubic-bezier(0.45, 0, 0.55, 1)'
export const easeInCubic = 'cubic-bezier(0.32, 0, 0.67, 0)'
export const easeOutCubic = 'cubic-bezier(0.33, 1, 0.68, 1)'
export const easeInOutCubic = 'cubic-bezier(0.65, 0, 0.35, 1)'
export const easeInQuart = 'cubic-bezier(0.5, 0, 0.75, 0)'
export const easeOutQuart = 'cubic-bezier(0.25, 1, 0.5, 1)'
export const easeInOutQuart = 'cubic-bezier(0.76, 0, 0.24, 1)'
export const easeInQuint = 'cubic-bezier(0.64, 0, 0.78, 0)'
export const easeOutQuint = 'cubic-bezier(0.22, 1, 0.36, 1)'
export const easeInOutQuint = 'cubic-bezier(0.83, 0, 0.17, 1)'
export const easeInExpo = 'cubic-bezier(0.7, 0, 0.84, 0)'
export const easeOutExpo = 'cubic-bezier(0.16, 1, 0.3, 1)'
export const easeInOutExpo = 'cubic-bezier(0.87, 0, 0.13, 1)'
export const easeInCirc = 'cubic-bezier(0.55, 0, 1, 0.45)'
export const easeOutCirc = 'cubic-bezier(0, 0.55, 0.45, 1)'
export const easeInOutCirc = 'cubic-bezier(0.85, 0, 0.15, 1)'
export const easeInBack = 'cubic-bezier(0.36, 0, 0.66, -0.56)'
export const easeOutBack = 'cubic-bezier(0.34, 1.56, 0.64, 1)'
export const easeInOutBack = 'cubic-bezier(0.68, -0.6, 0.32, 1.6)'

export const CUBIC_BEZIER_EASES = {
  easeInSine,
  easeOutSine,
  easeInOutSine,
  easeInQuad,
  easeOutQuad,
  easeInOutQuad,
  easeInCubic,
  easeOutCubic,
  easeInOutCubic,
  easeInQuart,
  easeOutQuart,
  easeInOutQuart,
  easeInQuint,
  easeOutQuint,
  easeInOutQuint,
  easeInExpo,
  easeOutExpo,
  easeInOutExpo,
  easeInCirc,
  easeOutCirc,
  easeInOutCirc,
  easeInBack,
  easeOutBack,
  easeInOutBack,
} as const

export const getEasingValues = (easing: keyof typeof CUBIC_BEZIER_EASES) =>
  CUBIC_BEZIER_EASES[easing].match(/(\d+\.?\d*)/g)!.map(parseFloat)

// Easing functions
type EasingFunction = (progress: number) => number

interface EasingDictionary {
  linear: EasingFunction
  easeInQuad: EasingFunction
  easeOutQuad: EasingFunction
  easeInOutQuad: EasingFunction
  easeInCubic: EasingFunction
  easeOutCubic: EasingFunction
  easeInOutCubic: EasingFunction
  easeInQuart: EasingFunction
  easeOutQuart: EasingFunction
  easeInOutQuart: EasingFunction
  easeInQuint: EasingFunction
  easeOutQuint: EasingFunction
  easeInOutQuint: EasingFunction
  easeInSine: EasingFunction
  easeOutSine: EasingFunction
  easeInOutSine: EasingFunction
  easeInExpo: EasingFunction
  easeOutExpo: EasingFunction
  easeInOutExpo: EasingFunction
  easeInCirc: EasingFunction
  easeOutCirc: EasingFunction
  easeInOutCirc: EasingFunction
  easeInBack: EasingFunction
  easeOutBack: EasingFunction
  easeInOutBack: EasingFunction
  easeInElastic: EasingFunction
  easeOutElastic: EasingFunction
  easeInOutElastic: EasingFunction
  easeInBounce: EasingFunction
  easeOutBounce: EasingFunction
  easeInOutBounce: EasingFunction
}

const pow = Math.pow
const sqrt = Math.sqrt
const sin = Math.sin
const cos = Math.cos
const PI = Math.PI
const c1 = 1.70158
const c2 = c1 * 1.525
const c3 = c1 + 1
const c4 = (2 * PI) / 3
const c5 = (2 * PI) / 4.5

const bounceOut: EasingFunction = x => {
  const n1 = 7.5625
  const d1 = 2.75

  if (x < 1 / d1) {
    return n1 * x * x
  } else if (x < 2 / d1) {
    return n1 * (x -= 1.5 / d1) * x + 0.75
  } else if (x < 2.5 / d1) {
    return n1 * (x -= 2.25 / d1) * x + 0.9375
  } else {
    return n1 * (x -= 2.625 / d1) * x + 0.984375
  }
}

export const EASING_FUNCTIONS: EasingDictionary = {
  linear: x => x,
  easeInQuad(x) {
    return x * x
  },
  easeOutQuad(x) {
    return 1 - (1 - x) * (1 - x)
  },
  easeInOutQuad(x) {
    return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
  },
  easeInCubic(x) {
    return x * x * x
  },
  easeOutCubic(x) {
    return 1 - pow(1 - x, 3)
  },
  easeInOutCubic(x) {
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
  },
  easeInQuart(x) {
    return x * x * x * x
  },
  easeOutQuart(x) {
    return 1 - pow(1 - x, 4)
  },
  easeInOutQuart(x) {
    return x < 0.5 ? 8 * x * x * x * x : 1 - pow(-2 * x + 2, 4) / 2
  },
  easeInQuint(x) {
    return x * x * x * x * x
  },
  easeOutQuint(x) {
    return 1 - pow(1 - x, 5)
  },
  easeInOutQuint(x) {
    return x < 0.5 ? 16 * x * x * x * x * x : 1 - pow(-2 * x + 2, 5) / 2
  },
  easeInSine(x) {
    return 1 - cos((x * PI) / 2)
  },
  easeOutSine(x) {
    return sin((x * PI) / 2)
  },
  easeInOutSine(x) {
    return -(cos(PI * x) - 1) / 2
  },
  easeInExpo(x) {
    return x === 0 ? 0 : pow(2, 10 * x - 10)
  },
  easeOutExpo(x) {
    return x === 1 ? 1 : 1 - pow(2, -10 * x)
  },
  easeInOutExpo(x) {
    return x === 0 ? 0 : x === 1 ? 1 : x < 0.5 ? pow(2, 20 * x - 10) / 2 : (2 - pow(2, -20 * x + 10)) / 2
  },
  easeInCirc(x) {
    return 1 - sqrt(1 - pow(x, 2))
  },
  easeOutCirc(x) {
    return sqrt(1 - pow(x - 1, 2))
  },
  easeInOutCirc(x) {
    return x < 0.5 ? (1 - sqrt(1 - pow(2 * x, 2))) / 2 : (sqrt(1 - pow(-2 * x + 2, 2)) + 1) / 2
  },
  easeInBack(x) {
    return c3 * x * x * x - c1 * x * x
  },
  easeOutBack(x) {
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
  },
  easeInOutBack(x) {
    return x < 0.5
      ? (pow(2 * x, 2) * ((c2 + 1) * 2 * x - c2)) / 2
      : (pow(2 * x - 2, 2) * ((c2 + 1) * (x * 2 - 2) + c2) + 2) / 2
  },
  easeInElastic(x) {
    return x === 0 ? 0 : x === 1 ? 1 : -pow(2, 10 * x - 10) * sin((x * 10 - 10.75) * c4)
  },
  easeOutElastic(x) {
    return x === 0 ? 0 : x === 1 ? 1 : pow(2, -10 * x) * sin((x * 10 - 0.75) * c4) + 1
  },
  easeInOutElastic(x) {
    return x === 0
      ? 0
      : x === 1
        ? 1
        : x < 0.5
          ? -(pow(2, 20 * x - 10) * sin((20 * x - 11.125) * c5)) / 2
          : (pow(2, -20 * x + 10) * sin((20 * x - 11.125) * c5)) / 2 + 1
  },
  easeInBounce(x) {
    return 1 - bounceOut(1 - x)
  },
  easeOutBounce: bounceOut,
  easeInOutBounce(x) {
    return x < 0.5 ? (1 - bounceOut(1 - 2 * x)) / 2 : (1 + bounceOut(2 * x - 1)) / 2
  },
} as const

// onUpdate and onStart callback polyfills for the native `Element.animate` method
interface AnimateWithCallbacks extends KeyframeAnimationOptions {
  onStart?: () => void
  onUpdate?: (progress: number) => void
  onCancel?: () => void
  onFinish?: () => void
  onRemove?: () => void
}

export const animate = (
  element: HTMLElement,
  keyframes: Parameters<Animatable['animate']>[0],
  {onStart, onUpdate, onCancel, onFinish, onRemove, ...options}: AnimateWithCallbacks = {},
): Animation => {
  let rAF: number
  let previousProgress = -1

  const animation = element.animate(keyframes, options)
  animation.oncancel = () => {
    cancelAnimationFrame(rAF)
    if (onCancel) onCancel()
  }

  animation.onfinish = () => {
    cancelAnimationFrame(rAF)
    if (onStart) onStart()
    if (onUpdate) onUpdate(1)
    if (onFinish) onFinish()
  }

  animation.onremove = () => {
    cancelAnimationFrame(rAF)
    if (onRemove) onRemove()
  }

  const trackProgress = () => {
    if (animation.playState !== 'running') return

    const progress = animation.effect!.getComputedTiming().progress || 0
    if (onStart && progress && previousProgress < 0) onStart()
    if (onUpdate) onUpdate(progress)

    if (progress) previousProgress = progress
    rAF = requestAnimationFrame(trackProgress)
  }

  rAF = requestAnimationFrame(trackProgress)

  return animation
}
