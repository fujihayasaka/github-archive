import type React from 'react'
import {useState, useEffect, useRef, useCallback, useMemo} from 'react'
import {gsap} from 'gsap'
import {clsx} from 'clsx'

import {checkPrefersReducedMotion} from './../utils/platform'
import CopilotHead from './CopilotHead'

import Styles from './CopilotActivationProgressBar.module.css'

export interface CopilotActivationProgressBarProps {
  segmentPoints: number[]
  currentSegmentIndex: number
  color?: 'gradient' | 'purple'
  shouldUseLocalStorage?: boolean
}

const defaultProps: Partial<CopilotActivationProgressBarProps> = {
  color: 'gradient',
  shouldUseLocalStorage: false,
}

const IMAGES_COUNT = 32 // the number of the copilot head images
const STEP_PERCENT = 100 / IMAGES_COUNT
const STEP_MAX_NUM = 32
const SPARKLE_NUM = 20

const LOCAL_STORAGE_PROGRESS_KEY = 'copilot-activation-progress-bar.progress'

const CopilotActivationProgressBar: React.FC<CopilotActivationProgressBarProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {segmentPoints, currentSegmentIndex, color, shouldUseLocalStorage} = initializedProps

  const [isReady, setIsReady] = useState<boolean>(false)
  const [isRunning, setIsRunning] = useState<boolean>(false)
  const [shouldReduceMotion, setShouldReduceMotion] = useState<boolean>(false)

  const isInitCurrentPointIndex = useRef<boolean>(true)
  const currentSegmentIndexRef = useRef<number>(currentSegmentIndex)
  const currentProgress = useRef<number>(0)
  const currentSparkleIndex = useRef<number>(0)
  const isRunningRef = useRef<boolean>(isRunning)
  const progressBarWidth = useRef<number>(0)
  const timer = useRef<ReturnType<typeof setInterval> | null>(null)
  const copilotStopTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const copilotStepNum = useRef<number>(0)

  const tl = useRef<gsap.core.Timeline | null>(gsap.timeline({paused: true}))
  const sparklesRef = useRef<Array<HTMLDivElement | null>>([])
  const wrapperRef = useRef<HTMLDivElement>(null)
  const barRef = useRef<HTMLDivElement>(null)
  const barFillRef = useRef<HTMLDivElement>(null)
  const copilotHeadRef = useRef<HTMLDivElement>(null)

  const progress = useMemo(() => (segmentPoints[currentSegmentIndex] || 0) / 100, [currentSegmentIndex, segmentPoints])

  const updateProgress = useCallback((progressRatio: number) => {
    currentProgress.current = progressRatio
    const progressSize = currentProgress.current * progressBarWidth.current

    if (copilotHeadRef.current) copilotHeadRef.current.style.transform = `translateX(${progressSize}px)`
    if (barFillRef.current) barFillRef.current.style.transform = `scaleX(${currentProgress.current})`
  }, [])

  useEffect(() => {
    const onResize = () => {
      if (barRef.current) {
        progressBarWidth.current = barRef.current.clientWidth

        // Apply the saved starting point if necessary
        if (shouldUseLocalStorage && isInitCurrentPointIndex.current) {
          if (window.localStorage) {
            const savedProgress = JSON.parse(window.localStorage.getItem(LOCAL_STORAGE_PROGRESS_KEY) || 'null') || 0
            updateProgress(savedProgress)
          }
        } else {
          updateProgress(currentProgress.current)
        }

        if (isInitCurrentPointIndex.current) setIsReady(true)
      }
    }

    setShouldReduceMotion(checkPrefersReducedMotion())
    // eslint-disable-next-line github/prefer-observers
    window.addEventListener('resize', onResize)
    onResize()

    return () => {
      window.removeEventListener('resize', onResize)
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const animateProgressBar = useCallback(() => {
    const targetProgress = progress

    if (tl.current) tl.current.kill()

    const value = {p: currentProgress.current}

    const onAnimationend = (event: AnimationEvent) => {
      ;(event.target as HTMLElement).removeEventListener('animationend', onAnimationend)
    }

    let _currentProgress = currentProgress.current
    tl.current = gsap.timeline({
      onUpdate: () => {
        updateProgress(value.p)

        const intervalDigit = 40

        if (
          isRunningRef.current &&
          Math.floor(_currentProgress * intervalDigit) !== Math.floor(value.p * intervalDigit) &&
          Math.abs(value.p - targetProgress) > 0.015
        ) {
          currentSparkleIndex.current++
          if (currentSparkleIndex.current === sparklesRef.current.length) {
            currentSparkleIndex.current = 0
          }

          const targetSparkle = sparklesRef.current[currentSparkleIndex.current]
          if (targetSparkle) {
            targetSparkle.style.transform = `translate(${(
              (value.p + (Math.random() - 0.5) * 0.025) *
              progressBarWidth.current
            ).toFixed()}px, ${(-20 + Math.random() * 40).toFixed()}px)`

            // @ts-expect-error: The generated class name is valid
            const className = Styles[
              `CopilotActivationProgressBar__sparkle--anim-${Math.floor(Math.random() * 6)}`
            ] as string
            targetSparkle.classList.add(className)
            if (targetSparkle.children.length > 0) {
              ;(targetSparkle.children[0] as HTMLElement).style.animationDuration = `${(
                0.4 +
                Math.random() * 0.4
              ).toFixed(2)}s`
            }

            targetSparkle.addEventListener('animationend', (event: AnimationEvent) => {
              onAnimationend(event)
              targetSparkle.classList.remove(className)
            })
          }
        }
        _currentProgress = value.p
      },
    })

    tl.current.to(value, {
      p: targetProgress,
      duration: 1.2,
      ease: 'power2.inOut',
    })
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [progress, shouldUseLocalStorage])

  const tickStepNum = useCallback((targetStep: number, interval: number) => {
    if (timer.current) clearInterval(timer.current)

    timer.current = setInterval(() => {
      const newStepNum = copilotStepNum.current + 1

      if (targetStep === newStepNum) {
        if (timer.current) clearInterval(timer.current)
      }

      copilotStepNum.current = newStepNum === STEP_MAX_NUM ? 0 : newStepNum

      const copilotActivationProgress = copilotStepNum.current * STEP_PERCENT
      const copilotSvg = copilotHeadRef.current?.querySelector('svg')
      if (copilotSvg) copilotSvg.style.transform = `translateY(-${copilotActivationProgress}%)`
    }, interval)
  }, [])

  // Trigger the animation when moving forward
  useEffect(() => {
    const proceed = () => {
      if (copilotStopTimer.current) {
        clearTimeout(copilotStopTimer.current)
        copilotStopTimer.current = null
      }

      const needsUpdate = progress !== currentProgress.current

      if (needsUpdate) {
        // In case we're not using in a SPA, we'd always start the transition from 0 at page load
        // To prevent this, we save the progress locally
        if (shouldUseLocalStorage)
          window.localStorage.setItem(
            LOCAL_STORAGE_PROGRESS_KEY,
            JSON.stringify(Number.isFinite(progress) ? progress : 0),
          )

        if (shouldReduceMotion) {
          updateProgress(progress)
        } else {
          if (
            currentSegmentIndexRef.current < currentSegmentIndex ||
            (isInitCurrentPointIndex.current && currentSegmentIndex)
          ) {
            setIsRunning(true)
            tickStepNum(16, 35)

            copilotStopTimer.current = setTimeout(() => {
              copilotStopTimer.current = null
              setIsRunning(false)
              tickStepNum(32, 33)
            }, 1200)
          }

          animateProgressBar()
        }
      }

      if (isInitCurrentPointIndex.current) {
        isInitCurrentPointIndex.current = false
      }

      currentSegmentIndexRef.current = currentSegmentIndex
    }

    if (isInitCurrentPointIndex.current) {
      if (isReady) proceed()
    } else proceed()

    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentSegmentIndex, segmentPoints, isReady])

  useEffect(() => {
    isRunningRef.current = isRunning
  }, [isRunning])

  return (
    <div
      ref={wrapperRef}
      role="progressbar"
      className={clsx(
        Styles['CopilotActivationProgressBar'],
        shouldUseLocalStorage && !isReady && Styles['CopilotActivationProgressBar--hidden'],
      )}
      data-testid="copilot-activation-progress-bar"
      aria-label={`Copilot activation progress: ${progress * 100}%`}
    >
      <div className={Styles['CopilotActivationProgressBar__bar']} ref={barRef}>
        <div className={Styles['CopilotActivationProgressBar__barBase']} />
        <div
          ref={barFillRef}
          className={clsx(
            Styles['CopilotActivationProgressBar__barFill'],
            // @ts-expect-error: The generated class name is valid
            Styles[`CopilotActivationProgressBar__barFill--${color}`],
          )}
        />

        {segmentPoints.map((point, index) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <div key={index} className={Styles['CopilotActivationProgressBar__point']} style={{left: `${point}%`}} />
        ))}

        <div className={Styles['CopilotActivationProgressBar__sparklesWrapper']}>
          {[...Array(SPARKLE_NUM)].map((_, index) => (
            <div
              className={Styles['CopilotActivationProgressBar__sparkle']}
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={index}
              ref={el => (sparklesRef.current[index] = el)}
            >
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
                <path d="M7.53 1.282a.5.5 0 0 1 .94 0l.478 1.306a7.492 7.492 0 0 0 4.464 4.464l1.305.478a.5.5 0 0 1 0 .94l-1.305.478a7.492 7.492 0 0 0-4.464 4.464l-.478 1.305a.5.5 0 0 1-.94 0l-.478-1.305a7.492 7.492 0 0 0-4.464-4.464L1.282 8.47a.5.5 0 0 1 0-.94l1.306-.478a7.492 7.492 0 0 0 4.464-4.464Z" />
              </svg>
            </div>
          ))}
        </div>
      </div>

      <CopilotHead
        ref={copilotHeadRef}
        isRunning={isRunning}
        isLastStep={currentSegmentIndex === segmentPoints.length - 1}
      />
    </div>
  )
}

export default CopilotActivationProgressBar
