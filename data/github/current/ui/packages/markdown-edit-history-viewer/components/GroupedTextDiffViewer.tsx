import {Fragment} from 'react/jsx-runtime'

import type {GroupDiffComparison, LineModification, TextDiffProps, WordModification} from './grouped-text-diff'
import {textDiff} from './grouped-text-diff'
import styles from './GroupedTextDiffViewer.module.css'

const getBorderStyling = (modification: LineModification) => {
  switch (modification) {
    case 'ADDED':
      return styles.borderStylingAdded
    case 'REMOVED':
      return styles.borderStylingRemoved
    case 'EDITED':
      return styles.borderStylingChanged
    case 'UNCHANGED':
      return ''
  }
}

const getWordStyling = (modification: WordModification) => {
  switch (modification) {
    case 'ADDED':
      return styles.wordStylingAdded
    case 'REMOVED':
      return styles.wordStylingRemoved
    case 'UNCHANGED':
      return ''
  }
}

const getScreenReaderHint = (modification: LineModification | WordModification) => {
  switch (modification) {
    case 'ADDED':
      return {open: '[+]', close: '[/+]'}
    case 'REMOVED':
      return {open: '[-]', close: '[/-]'}
  }

  return {open: '', close: ''}
}

const needsScreenReaderHint = (modification: LineModification | WordModification) => {
  return modification === 'ADDED' || modification === 'REMOVED'
}

const LineDiffViewer = ({groups, modification}: GroupDiffComparison) => {
  const fullSentence = groups.map(group => group.words).join(' ')
  return (
    <span className={styles.diffLine}>
      {modification === 'EDITED' &&
        groups?.map((group, index) => {
          return (
            // eslint-disable-next-line @eslint-react/no-array-index-key
            <Fragment key={index - 1}>
              {needsScreenReaderHint(group.modification) && (
                <span className="sr-only">{getScreenReaderHint(group.modification).open}</span>
              )}
              <span className={getWordStyling(group.modification)}>{`${index === 0 ? '' : ' '}${group.words}`}</span>
              {needsScreenReaderHint(group.modification) && (
                <span className="sr-only">{getScreenReaderHint(group.modification).close}</span>
              )}
            </Fragment>
          )
        })}
      {modification !== 'EDITED' && groups.length > 0 && (
        <>
          <span className="sr-only">{getScreenReaderHint(modification).open}</span>
          <span>{fullSentence}</span>
          <span className="sr-only">{getScreenReaderHint(modification).close}</span>
        </>
      )}
      {groups.length === 0 && <br />}
    </span>
  )
}

export const GroupedTextDiffViewer = ({before, after}: TextDiffProps) => {
  const groupDiffSummary = textDiff({before, after})

  return (
    <div className={styles.diffContainer}>
      {groupDiffSummary.lines.map((line, index) => {
        return (
          <div
            // eslint-disable-next-line @eslint-react/no-array-index-key
            key={index}
            className={getBorderStyling(line.modification)}
          >
            <LineDiffViewer {...line} />
          </div>
        )
      })}
    </div>
  )
}
