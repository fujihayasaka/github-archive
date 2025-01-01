import ProductivityLeft from './fixtures/images/productivity-shape-left.webp'
import ProductivityRight from './fixtures/images/productivity-shape-right.webp'
import CollaborationLeft from './fixtures/images/collaboration-shape-left.webp'
import CollaborationRight from './fixtures/images/collaboration-shape-right.webp'
import AILeft from './fixtures/images/ai-shape-left.webp'
import AIRight from './fixtures/images/ai-shape-right.webp'
import SecurityLeft from './fixtures/images/security-shape-left.webp'
import SecurityRight from './fixtures/images/security-shape-right.webp'
import EnterpriseLeft from './fixtures/images/enterprise-shape-left.webp'
import EnterpriseRight from './fixtures/images/enterprise-shape-right.webp'
import type {BoxSpacingValues} from '@primer/react-brand'
import styles from './FlexSectionTestimonials.module.css'

type SpacingValues = (typeof BoxSpacingValues)[number]

type BackgroundStyleProps = {
  marginBlockStart: SpacingValues
  marginBlockEnd: SpacingValues
  className: string
  left: {
    image: string
    width: number
  }
  right: {
    image: string
    width: number
  }
}

type BackgroundStylesMapProps = {
  Productivity: BackgroundStyleProps
  Collaboration: BackgroundStyleProps
  AI: BackgroundStyleProps
  Security: BackgroundStyleProps
  Enterprise: BackgroundStyleProps
}

export const backgroundStylesMap: BackgroundStylesMapProps = {
  Productivity: {
    className: styles.productivity,
    marginBlockStart: 'none',
    marginBlockEnd: 16,
    left: {
      image: ProductivityLeft,
      width: 444,
    },
    right: {
      image: ProductivityRight,
      width: 574,
    },
  },
  Collaboration: {
    className: styles.collaboration,
    marginBlockStart: 24,
    marginBlockEnd: 'none',
    left: {
      image: CollaborationLeft,
      width: 426,
    },
    right: {
      image: CollaborationRight,
      width: 417,
    },
  },
  AI: {
    className: styles.ai,
    marginBlockStart: 'none',
    marginBlockEnd: 'none',
    left: {
      image: AILeft,
      width: 424,
    },
    right: {
      image: AIRight,
      width: 433,
    },
  },
  Security: {
    className: styles.security,
    marginBlockStart: 8,
    marginBlockEnd: 'none',
    left: {
      image: SecurityLeft,
      width: 349,
    },
    right: {
      image: SecurityRight,
      width: 521,
    },
  },
  Enterprise: {
    className: styles.enterprise,
    marginBlockStart: 'none',
    marginBlockEnd: 128,
    left: {
      image: EnterpriseLeft,
      width: 418,
    },
    right: {
      image: EnterpriseRight,
      width: 433,
    },
  },
}
