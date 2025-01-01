import {AnimationProvider, Box} from '@primer/react-brand'

import styles from './Category.module.css'

export const GlowBackground = () => (
  <AnimationProvider runOnce visibilityOptions={0.1} autoStaggerChildren>
    <Box className={styles.glowieWrapper}>
      <Box animate="fade-in" className={`${styles.glowie} ${styles.left}`} />
      <Box animate="fade-in" className={`${styles.glowie} ${styles.right}`} />
    </Box>
  </AnimationProvider>
)
