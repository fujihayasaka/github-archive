import FeaturesTable from './../../generic/FeaturesTable/FeaturesTable'
import type {FeaturesTableProps} from './../../generic/FeaturesTable/FeaturesTable'

import Styles from './Features.module.css'

export interface FeaturesProps {
  categories: FeaturesTableProps[]
}

const defaultProps: Partial<FeaturesProps> = {}

const Features: React.FC<FeaturesProps> = props => {
  const initializedProps = {...defaultProps, ...props}

  const {categories} = initializedProps

  return (
    <section id="features" className={Styles['Features']}>
      <div className={Styles['Features__container']}>
        <div className={Styles['Features__tablesWrapper']}>
          {categories.map((category, index) => (
            // eslint-disable-next-line @eslint-react/no-array-index-key
            <FeaturesTable key={`category_${index}`} {...category} />
          ))}
        </div>
      </div>
    </section>
  )
}

export default Features
