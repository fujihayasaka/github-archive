import {Banner} from '@primer/react/experimental'

interface Props {
  numDeleted: number
}

export function DeletedReposBanner({numDeleted}: Props) {
  const numDeletedReposWord = numDeleted === 1 ? 'repository' : 'repositories'
  const haveWord = numDeleted === 1 ? 'has' : 'have'

  const content = `${numDeleted} ${numDeletedReposWord} used in training ${haveWord} since been deleted.`

  return (
    <Banner
      description={
        <>
          <Banner.Title style={{display: 'none'}}>{content}</Banner.Title>
          <span>{content}</span>
        </>
      }
      variant="info"
    />
  )
}
