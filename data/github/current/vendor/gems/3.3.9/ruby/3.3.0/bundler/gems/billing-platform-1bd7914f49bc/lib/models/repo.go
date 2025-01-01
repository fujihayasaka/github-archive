package models

import "fmt"

type Repo struct {
	*RepoKey
	IsPublic bool
}

type RepoKey struct {
	*Key
	RepoId int64
}

func NewRepo(repoId int64, isPublic bool) *Repo {
	return &Repo{
		RepoKey:  NewRepoKey(repoId),
		IsPublic: isPublic,
	}
}

func NewRepoKey(repoId int64) *RepoKey {
	return &RepoKey{
		Key: &Key{
			Id:           fmt.Sprintf("%d", repoId),
			PartitionKey: "repos",
		},
		RepoId: repoId,
	}
}

func (r *Repo) GetIsPublic() bool {
	return r.IsPublic
}

func (r *Repo) GetId() uint64 {
	return uint64(r.RepoId)
}

type RepoMetadata interface {
	GetId() uint64
	GetIsPublic() bool
}
