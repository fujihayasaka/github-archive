import {makeSourceRepos} from '../docset'

describe('makeSourceRepos', () => {
  const repos = [
    {
      databaseId: 1,
      name: 'bar',
      nameWithOwner: 'foo/bar',
      isInOrganization: true,
      shortDescriptionHTML: '',
      paths: [],
      owner: {
        databaseId: 2,
        login: 'foo',
        avatarUrl: '/foo',
      },
    },
    {
      databaseId: 2,
      name: 'baz',
      nameWithOwner: 'foo/baz',
      isInOrganization: true,
      shortDescriptionHTML: '',
      paths: ['/docs/**'],
      owner: {
        databaseId: 3,
        login: 'foo',
        avatarUrl: '/foo',
      },
    },
    {
      databaseId: 3,
      name: 'bam',
      nameWithOwner: 'foo/bam',
      isInOrganization: true,
      shortDescriptionHTML: 'hello',
      paths: ['/docs/**', '/docs/'],
      owner: {
        databaseId: 4,
        login: 'foo',
        avatarUrl: '/foo',
      },
    },
  ]

  it('returns correct components', () => {
    const sourceRepos = makeSourceRepos(repos)

    expect(sourceRepos.length).toEqual(repos.length)
    for (const [i, repo] of repos.entries()) {
      expect(sourceRepos[i]).toEqual({
        id: repo.databaseId,
        ownerID: repo.owner.databaseId,
        paths: repo.paths,
      })
    }
  })
})
