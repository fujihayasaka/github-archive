import {useEffect, useRef} from 'react'

import styles from './CanvasParticles.module.css'

const PARTICLE_SIZE = 14
const PARTICLE_COUNT = 80

const COLORS = [
  '#218bff', // Accent color
  '#2da44e', // Success color
  '#8250df', // Done color
  '#d1242f', // Attention color
] as const
const SHAPES = [
  'M12 7A5 5 0 1 1 2 7a5 5 0 0 1 10 0Z', // circle
  'M3 3h8v8H3V3Z', // square
  'M14 7C9.284 5.653 8.237 4.524 7 0 5.763 4.524 4.715 5.653 0 7c4.716 1.347 5.763 2.476 7 7 1.237-4.524 2.284-5.653 7-7Z', // star
] as const

export function CanvasParticles() {
  const containerRef = useRef<HTMLDivElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const particlesRef = useRef<ReturnType<typeof createParticles> | null>(null)
  const animationRef = useRef<number | null>(null)

  // Animation effect
  useEffect(() => {
    const canvas = canvasRef.current
    const container = containerRef.current
    if (!canvas || !container) return

    let width = container.clientWidth
    let height = container.clientHeight
    let dpr = Math.min(window.devicePixelRatio, 2)

    canvas.width = width * dpr
    canvas.height = height * dpr

    const ctx = canvas.getContext('2d')
    if (!ctx) return

    ctx.setTransform(1, 0, 0, 1, 0, 0)
    ctx.scale(dpr, dpr)

    // Initialize particles
    particlesRef.current = createParticles(width, height)

    let lastTime = performance.now()

    function animate(now: number) {
      const deltaTime = (now - lastTime) / 16.667
      lastTime = now

      if (particlesRef.current && ctx) {
        particlesRef.current = particlesRef.current.map(p => updateParticle(p, width, height, deltaTime))
        drawParticles(ctx, particlesRef.current, width, height)
      }

      animationRef.current = requestAnimationFrame(animate)
    }

    animationRef.current = requestAnimationFrame(animate)

    // Resize observer for container
    const resizeObserver = new ResizeObserver(entries => {
      const entry = entries[0]
      if (entry && canvas) {
        width = entry.contentRect.width
        height = entry.contentRect.height
        dpr = Math.min(window.devicePixelRatio, 2)
        canvas.width = width * dpr
        canvas.height = height * dpr
        ctx.setTransform(1, 0, 0, 1, 0, 0)
        ctx.scale(dpr, dpr)
      }
    })
    resizeObserver.observe(container)

    return () => {
      if (animationRef.current) cancelAnimationFrame(animationRef.current)
      resizeObserver.disconnect()
    }
  }, [])

  return (
    <div ref={containerRef} className={styles.container}>
      <canvas ref={canvasRef} className={styles.canvas} />
    </div>
  )
}

// Helper functions
const map = (value: number, start1: number, stop1: number, start2: number, stop2: number) => {
  const scale = 1 / (stop1 - start1)
  const mapped = (value - start1) * scale * (stop2 - start2) + start2
  return mapped < 0 ? 0 : mapped > 1 ? 1 : mapped
}

const random = <T,>(array: readonly T[]): T => {
  // Ensure array is not empty to satisfy type system
  if (array.length === 0) {
    throw new Error('Cannot get random element from empty array')
  }
  // Using non-null assertion since we know array has elements
  return array[Math.floor(Math.random() * array.length)]!
}

// Particle functions
const createParticle = (width: number, height: number, initial = false, initialProgress = 0) => {
  const x = Math.random()
  const y = initial ? 1 + 0.8 * (1 - initialProgress) : 1.05
  const scale = 0.8 + Math.random() * 0.9
  const baseSpeed = 0.00035
  const speed = -(baseSpeed + Math.random() * baseSpeed * 0.1)
  const color = random(COLORS)
  const shape = new Path2D(random(SHAPES))
  const rotation = Math.random() * Math.PI * 2
  return {x, y, scale, speed, color, shape, rotation}
}

const createParticles = (width: number, height: number) => {
  const particles = Array.from({length: PARTICLE_COUNT}, (_, index) =>
    createParticle(width, height, true, index / PARTICLE_COUNT),
  )
  return particles
}

const drawParticles = (
  ctx: CanvasRenderingContext2D,
  particles: ReturnType<typeof createParticles>,
  width: number,
  height: number,
) => {
  ctx.clearRect(0, 0, width, height)
  for (const p of particles) {
    ctx.save()
    ctx.translate(p.x * width, p.y * height)
    ctx.rotate(p.rotation)
    ctx.scale(p.scale, p.scale)
    ctx.fillStyle = p.color
    ctx.translate(PARTICLE_SIZE / 2, PARTICLE_SIZE / 2)
    ctx.fill(p.shape)
    ctx.restore()
  }
}

const updateParticle = (
  particle: ReturnType<typeof createParticle>,
  width: number,
  height: number,
  deltaTime: number,
) => {
  const safeDeltaTime = Math.min(deltaTime, 32)
  const {speed, color, shape} = particle
  const x = particle.x
  let y = particle.y
  let scale = particle.scale
  let rotation = particle.rotation

  y += speed * safeDeltaTime
  rotation += 0.01 * safeDeltaTime

  const fadeEnd = 0.1

  scale = map(y, 1, 0, 1, 0.6)

  // If faded out, respawn
  if (y <= fadeEnd) {
    return createParticle(width, height, false)
  }

  return {x, y, scale, speed, color, shape, rotation}
}
