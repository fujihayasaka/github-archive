import type {RefObject} from 'react'
import type React from 'react'
import {useRef, useCallback, lazy, Suspense} from 'react'

import {SectionIntro as PrimerSectionIntro} from '@primer/react-brand'
import type {SectionIntroWebGLProps} from '../SectionIntroWebGL/SectionIntroWebGL'

import {Spacer} from '../../_shared/Spacer'
import type Assets from '../../webgl-utils/assets'
import {useDomReady} from '../../../../lib/utils/platform'

const SectionIntroWebGL = lazy(() => import('../SectionIntroWebGL/SectionIntroWebGL'))

export interface SectionIntroProps {
  mascot: SectionIntroWebGLProps['mascotName']
  title: string
  description?: string
  bottomSpacerSize?: 'default' | 'small'
  isWebGLMascotOnly?: boolean
  assetsRef: React.RefObject<Assets>
}

const SectionIntro: React.FC<SectionIntroProps> = ({
  mascot,
  title,
  description,
  bottomSpacerSize = 'default',
  isWebGLMascotOnly = false,
  assetsRef,
}) => {
  const mascotRef = useRef<HTMLDivElement | null>(null)
  const containerRef = useRef<HTMLDivElement | null>(null)
  const introContent = useRef<HTMLDivElement | null>(null)
  const isDomReady = useDomReady()

  const startCopyAnimation = useCallback(() => {
    if (introContent.current) {
      introContent.current.classList.add('is-visible')
    }
  }, [])

  return (
    <div className="lp-SectionIntro" ref={containerRef as RefObject<HTMLDivElement>}>
      <Spacer size="96px" size1012="148px" />
      {isDomReady && (
        <Suspense fallback={null}>
          <SectionIntroWebGL
            mascotName={mascot}
            mascotRef={mascotRef}
            containerRef={containerRef}
            isMascotOnly={isWebGLMascotOnly}
            startCopyAnimation={startCopyAnimation}
            assetsRef={assetsRef}
          />
        </Suspense>
      )}
      <div className="lp-SectionIntro-mascot" ref={mascotRef as RefObject<HTMLDivElement>} />

      <PrimerSectionIntro
        className="lp-SectionIntro-content"
        align="center"
        fullWidth
        ref={introContent as RefObject<HTMLDivElement>}
      >
        <PrimerSectionIntro.Heading as="h2" size="3" className="lp-SectionIntro-heading">
          {/* eslint-disable-next-line react/no-danger */}
          <div dangerouslySetInnerHTML={{__html: title}} />
        </PrimerSectionIntro.Heading>

        {description && (
          <PrimerSectionIntro.Description className="lp-SectionIntro-description">
            {/* eslint-disable-next-line react/no-danger */}
            <span dangerouslySetInnerHTML={{__html: description}} />
          </PrimerSectionIntro.Description>
        )}
      </PrimerSectionIntro>

      <Spacer
        size={`${bottomSpacerSize === 'small' ? 32 : 40}px`}
        size1012={`${bottomSpacerSize === 'small' ? 56 : 80}px`}
      />
    </div>
  )
}

export default SectionIntro
