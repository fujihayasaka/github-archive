package repositories

import (
	"bytes"
	"fmt"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"

	"github.com/github/spokes-proto/gen/go/v1/extensions"
)

func (req *ListAvailableReplicasRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	return nil
}

func (req *CreateForkRequest) Validate() error {
	if req.GetParent().GetRepository() == nil {
		return twirp.RequiredArgumentError("parent.repository")
	}

	if err := req.GetParent().GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetFork() == nil {
		return twirp.RequiredArgumentError("fork")
	}

	if req.GetFork().GetId() == req.GetParent().GetRepository().GetId() {
		return twirp.InvalidArgumentError("fork.id", "cannot be the same as parent repository id")
	}

	if len(req.GetFork().GetNwo()) == 0 {
		return twirp.RequiredArgumentError("fork.nwo")
	}

	switch req.GetParent().GetRepository().GetType() {
	case types.Repository_TYPE_REPOSITORY:
	case types.Repository_TYPE_GIST:
	default:
		return twirp.InvalidArgumentError("parent.repository.type", "enum must be of type repository or gist")
	}

	if req.GetBranchMode() == CreateForkRequest_BRANCH_MODE_INVALID {
		return twirp.InvalidArgumentError("branch_mode", "must be set")
	}

	return nil
}

func (req *GetRepositoryMetadataRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	return nil
}

func (req *CreateRepositoryRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if len(req.GetNwo()) == 0 {
		return twirp.RequiredArgumentError("nwo")
	}

	if req.GetDefaultBranch() == nil {
		return twirp.RequiredArgumentError("default_branch")
	}
	if err := req.GetDefaultBranch().ValidateFormat(); err != nil {
		return err
	}
	if !bytes.HasPrefix(req.GetDefaultBranch().GetName(), []byte("refs/heads/")) {
		return twirp.InvalidArgumentError("reference.name", "must have a 'refs/heads/' prefix")
	}

	if req.GetInitialCommit() != nil {
		initialCommit := req.GetInitialCommit()

		if initialCommit.GetAuthor() == nil {
			return twirp.RequiredArgumentError("author")
		}
		if err := initialCommit.GetAuthor().Validate(); err != nil {
			return err
		}

		if initialCommit.GetCommitter() == nil {
			return twirp.RequiredArgumentError("committer")
		}
		if err := initialCommit.GetCommitter().Validate(); err != nil {
			return err
		}

		fileCount := len(initialCommit.GetFiles())
		if fileCount == 0 {
			return twirp.RequiredArgumentError("files")
		}

		desc := initialCommit.ProtoReflect().Descriptor().Fields().ByName("files")
		fileLimit := int(proto.GetExtension(desc.Options(), extensions.E_Limit).(uint32))
		if fileLimit > 0 && fileCount > fileLimit {
			return twirp.InvalidArgumentError("files", fmt.Sprintf("may contain up to %d items", fileLimit))
		}

		for _, file := range initialCommit.GetFiles() {
			if file.GetPath() == nil {
				return twirp.RequiredArgumentError("files.path")
			}
			if err := file.GetPath().Validate(); err != nil {
				return err
			}
			if bytes.Contains(file.GetPath().GetName(), []byte("/")) {
				return twirp.InvalidArgumentError("files.path", "only root-level files are supported")
			}
		}
	}

	return nil
}
