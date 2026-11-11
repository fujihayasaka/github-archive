// Package configs provides the configuration service implementation.
package configs

import (
	"context"

	"github.com/github/configsd/internal/model"
	"github.com/twitchtv/twirp"
	timestamppb "google.golang.org/protobuf/types/known/timestamppb"
)

// Service implements the Configs interface for configuration resolution.
type Service struct {
	store model.Store
}

// NewConfigsService creates a new instance of the Configs service.
func NewConfigsService(store model.Store) Configs {
	return &Service{
		store: store,
	}
}

// ResolveConfigsByTarget resolves configurations for a given target by walking the hierarchy
// and merging configurations based on precedence rules.
func (s *Service) ResolveConfigsByTarget(ctx context.Context, req *ResolveConfigsByTargetRequest) (*ResolveConfigsByTargetResponse, error) {
	if req == nil || req.Target == nil {
		return nil, twirp.InvalidArgumentError("target", "target is required")
	}

	// Convert protobuf target type to model target type
	targetType, err := protoTargetTypeToModel(req.Target.Type)
	if err != nil {
		return nil, err
	}

	// Convert protobuf target to internal model
	target := model.ConfigurationTarget{Type: targetType, ID: req.Target.Id}

	// Get all properties for the target (store handles hierarchy resolution)
	resolvedConfigs, err := s.store.AllProperties(ctx, target)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	// Convert resolved configurations to protobuf format
	responseConfigs := make(map[string]*Config)
	for name, config := range resolvedConfigs {
		responseConfigs[name] = ToTwirpConfig(&config)
	}

	return &ResolveConfigsByTargetResponse{
		Configs: &ResolvedConfigs{
			Configs: responseConfigs,
		},
	}, nil
}

// ResolveConfigsByTargetWithOwners resolves configurations for a target specified with owner information.
func (s *Service) ResolveConfigsByTargetWithOwners(ctx context.Context, req *ResolveConfigsByTargetWithOwnersRequest) (*ResolveConfigsByTargetResponse, error) {
	if req == nil || req.Target == nil {
		return nil, twirp.InvalidArgumentError("target", "target is required")
	}

	// Build ordered array of targets from owner information
	targets, err := configTargetWithOwnersToTargets(req.Target)
	if err != nil {
		return nil, err
	}

	// Get all properties resolved for the hierarchy of each target
	resolvedConfigs, err := s.store.ResolvedConfigsByTargetWithOwners(ctx, targets)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	// Convert resolved configurations to protobuf format
	responseConfigs := make(map[string]*Config)
	for name, config := range resolvedConfigs {
		responseConfigs[name] = ToTwirpConfig(&config)
	}

	return &ResolveConfigsByTargetResponse{
		Configs: &ResolvedConfigs{
			Configs: responseConfigs,
		},
	}, nil
}

// ResolveConfigsByTargetsWithOwners - empty stub implementations to satisfy interface
func (s *Service) ResolveConfigsByTargetsWithOwners(ctx context.Context, req *ResolveConfigsByTargetsWithOwnersRequest) (*ResolveConfigsByTargetsWithOwnersResponse, error) {
	return &ResolveConfigsByTargetsWithOwnersResponse{
		ConfigsByType: make(map[uint32]*ResolvedConfigsById),
	}, nil
}

// configTargetWithOwnersToTargets converts ConfigTargetWithOwners to an ordered slice of ConfigurationTargets.
// The targets are ordered from most specific to most general: Repository -> User -> Business -> Global.
func configTargetWithOwnersToTargets(target *ConfigTargetWithOwners) ([]model.ConfigurationTarget, error) {
	var targets []model.ConfigurationTarget

	if target.RepoId != 0 {
		repoTarget := model.ConfigurationTarget{Type: model.Repository, ID: target.RepoId}
		targets = append(targets, repoTarget)
	}

	if target.OwnerId != 0 {
		ownerTarget := model.ConfigurationTarget{Type: model.User, ID: target.OwnerId}
		targets = append(targets, ownerTarget)
	}

	if target.BusinessId != 0 {
		businessTarget := model.ConfigurationTarget{Type: model.Business, ID: target.BusinessId}
		targets = append(targets, businessTarget)
	}

	// Always append Global as the final fallback
	targets = append(targets, model.GlobalTarget)

	return targets, nil
}

// ToTwirpConfig converts a Configuration to a twirp Config message.
func ToTwirpConfig(c *model.Configuration) *Config {
	if c == nil {
		return nil
	}

	config := &Config{
		Name:  c.Name,
		Value: c.Value,
		Final: c.Final,
	}

	if c.Target != nil {
		// Convert string type back to TargetType enum
		var targetType TargetType
		switch c.Target.Type {
		case model.Repository:
			targetType = TargetType_Repository
		case model.User:
			targetType = TargetType_User
		case model.Business:
			targetType = TargetType_Business
		case model.Global:
			targetType = TargetType_Global
		default:
		}

		config.Target = &ConfigTarget{
			Id:   c.Target.ID,
			Type: targetType,
		}
	}

	if !c.CreatedAt.IsZero() {
		config.CreatedAt = timestamppb.New(c.CreatedAt)
	}

	if !c.UpdatedAt.IsZero() {
		config.UpdatedAt = timestamppb.New(c.UpdatedAt)
	}

	return config
}

// protoTargetTypeToModel converts a protobuf TargetType enum to a model.TargetType.
func protoTargetTypeToModel(protoType TargetType) (model.TargetType, error) {
	switch protoType {
	case TargetType_Repository:
		return model.Repository, nil
	case TargetType_User:
		return model.User, nil
	case TargetType_Business:
		return model.Business, nil
	case TargetType_Global:
		return model.Global, nil
	default:
		return "", twirp.InvalidArgumentError("target.type", "unsupported target type")
	}
}
