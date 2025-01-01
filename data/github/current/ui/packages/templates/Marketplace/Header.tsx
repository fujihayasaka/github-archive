import styled, {keyframes, css} from 'styled-components'
import {Box, Heading, TextInput, useResponsiveValue, type ResponsiveValue} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {SearchIcon} from '@primer/octicons-react'

import styles from './Header.module.css'

const floatAnimation = (distance: number) => keyframes`
  0% {
    transform: translatey(0px);
  }
  50% {
    transform: translatey(${distance}px);
  }
  100% {
    transform: translatey(0px);
  }
`
const floatAndScaleAnimation = (distance: number) => keyframes`
  0% {
    transform: translatey(0px) scale(1);
  }
  50% {
    transform: translatey(${distance}px) scale(0.9);
  }
  100% {
    transform: translatey(0px) scale(1);
  }
`

const ScaleFloatAnimation = styled.div<{distance?: number; delay?: number}>`
  animation: ${props => css`
      ${floatAndScaleAnimation(props.distance || -5)}
    `}
    2s ease-in-out infinite;
  animation-delay: ${props => props.delay ?? 0}s;
`
const FloatAnimation = styled.div<{distance?: number; delay?: number}>`
  animation: ${props => css`
      ${floatAnimation(props.distance || -5)}
    `}
    2s ease-in-out infinite;
  animation-delay: ${props => props.delay ?? 0}s;
`

export default function Header() {
  const mobilePlaceholder = 'Search our marketplace'
  const desktopPlaceholder = 'Search for Copilot plugins, apps, and actions'
  const searchPlaceholder = useResponsiveValue(
    {narrow: mobilePlaceholder, regular: desktopPlaceholder} as ResponsiveValue<string>,
    desktopPlaceholder,
  )

  return (
    <div className={styles.Box}>
      <div className={styles.Box_1}>
        <div className={styles.Box_2}>
          <div className={styles.Box_3}>
            <Heading as="h1" className={styles.Heading}>
              Extend GitHub
            </Heading>
            <span className={styles.Text}>Tools from the community and partners to help you build.</span>
          </div>
          <div className={styles.Box_4}>
            <TextInput
              size="large"
              leadingVisual={<Octicon icon={SearchIcon} />}
              placeholder={searchPlaceholder}
              aria-label="Search"
              autoFocus
              className={styles.TextInput}
            />
          </div>
        </div>
        <div className={styles.Box_5}>
          <div id="gradient-shape" className={styles.Box_6} />
          <Box
            as="img"
            sx={{
              filter: 'blur(6.095px)',
              width: 284,
              height: 284,
              position: 'absolute',
              top: -150,
              right: [-150, -150, -120],
            }}
            id="circle-shape"
            alt="Circular shape"
            src="https://github.com/primer/design/assets/980622/b5881923-9b0c-44b1-b392-b2384b878252"
            srcSet={`https://github.com/primer/design/assets/980622/1293164f-e8fb-4a79-a84a-a18832ad6cef 1x, https://github.com/primer/design/assets/980622/4b538318-b1b5-4954-b997-6d368fddbab3 2x, https://github.com/primer/design/assets/980622/2f5d9680-fb8f-4d67-a307-747e6da3140b 3x`}
          />
          <Box
            as="img"
            sx={{
              width: 340,
              height: 340,
              position: 'absolute',
              top: [30, 30, 140],
              left: [-260, -260, -200],
              filter: 'blur(6.76px)',
            }}
            id="insect-shape"
            alt="Insect shape"
            src="https://github.com/primer/design/assets/980622/b5f5c7cd-9264-4579-a8bb-9de5993ca5a6"
            srcSet={`https://github.com/primer/design/assets/980622/b5f5c7cd-9264-4579-a8bb-9de5993ca5a6 1x, https://github.com/primer/design/assets/980622/4fd35bc4-2348-43ea-8ca0-f0de8d89aabf 2x, https://github.com/primer/design/assets/980622/44ff1f88-f9f7-4834-9b33-08d2aab8debd 3x`}
          />
          <Box
            as="img"
            sx={{
              width: 281,
              height: 281,
              position: 'absolute',
              bottom: [-130, -130, -100],
              right: [-160, -160, -120],
            }}
            id="combo-shape"
            alt="Combination of shapes"
            src="https://github.com/primer/design/assets/980622/e4298b09-dc8f-47e6-8306-5c6ca7fdb2c4"
            srcSet={`https://github.com/primer/design/assets/980622/e4298b09-dc8f-47e6-8306-5c6ca7fdb2c4 1x, https://github.com/primer/design/assets/980622/59f2efc3-9cdf-47aa-a0fe-3cdc21343770 2x, https://github.com/primer/design/assets/980622/52a72075-4f3b-4b4e-8683-a4725c903899 3x`}
          />

          <Box
            sx={{
              position: 'absolute',
              top: [-50],
              left: [0, 0, -100],
            }}
          >
            <FloatAnimation delay={1.1}>
              <img
                alt="Rectangular shape"
                id="block-shape"
                src="https://github.com/primer/design/assets/980622/cd212da7-8d13-4d52-bf6e-a2e00c7a30e8"
                srcSet={`https://github.com/primer/design/assets/980622/cd212da7-8d13-4d52-bf6e-a2e00c7a30e8 1x, https://github.com/primer/design/assets/980622/1eb12ab2-da66-4ce3-9e18-89dfe5a2ef43 2x, https://github.com/primer/design/assets/980622/5be61d1a-d9d0-4d12-942c-3fae4d9cb602 3x`}
                className={styles.Box_7}
              />
            </FloatAnimation>
          </Box>

          <div className={styles.Box_8}>
            <ScaleFloatAnimation delay={0.5} distance={2}>
              <img
                id="big-star"
                alt="Big star"
                src="https://github.com/primer/design/assets/980622/13fd451c-6a55-4c72-b675-8ccd82786a34"
                srcSet={`https://github.com/primer/design/assets/980622/13fd451c-6a55-4c72-b675-8ccd82786a34 1x, https://github.com/primer/design/assets/980622/840922b7-7aa9-447f-9dec-1817615a95d9 2x, https://github.com/primer/design/assets/980622/c5d2fd32-3fdb-4623-81bc-4610a38b674b 3x`}
                className={styles.Box_9}
              />
            </ScaleFloatAnimation>
          </div>

          <div className={styles.Box_10}>
            <ScaleFloatAnimation delay={1.1} distance={1}>
              <img
                alt="Little star"
                id="small-star"
                src="https://github.com/primer/design/assets/980622/17897fc0-dc69-43d6-9281-1d501d5c6460"
                srcSet={`https://github.com/primer/design/assets/980622/17897fc0-dc69-43d6-9281-1d501d5c6460 1x, https://github.com/primer/design/assets/980622/5a6cc2fc-a15e-4a2d-9fcd-614a39d5047f 2x, https://github.com/primer/design/assets/980622/9eabedae-57bd-4b09-bb0a-43f38d43b9bf 3x`}
                className={styles.Box_11}
              />
            </ScaleFloatAnimation>
          </div>

          <Box
            sx={{
              position: 'absolute',
              top: [20, 20, 0],
              right: 0,
              left: ['50%', '50%', 'auto'],
              ml: [-140, -140, 'auto'],
            }}
          >
            <FloatAnimation>
              <img
                alt="Copilot mascot head"
                id="head"
                src="https://github.com/primer/design/assets/980622/4a87a305-24df-4ffb-93fb-26bf01134233"
                srcSet={`https://github.com/primer/design/assets/980622/4a87a305-24df-4ffb-93fb-26bf01134233 1x, https://github.com/primer/design/assets/980622/ffeaa854-5620-4e0f-943d-7bbb627cdd7f 2x, https://github.com/primer/design/assets/980622/6038b673-e7d0-4a88-bb7c-b38b0e1e4cd7 3x`}
                className={styles.Box_12}
              />
            </FloatAnimation>
          </Box>
        </div>
      </div>
    </div>
  )
}
