package jobservice

import (
	"context"
	"strings"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/sweagentd"
)

func (s *Service) LabelMetadataForJob(ctx context.Context, actors sweagentd.RepositoryWithActor, labelable github.Labelable) sweagentd.LabelMetadata {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.LabelMetadataForJob")
	defer span.End()

	return LabelMetadataForJob(ctx, s.ffs, actors, labelable)
}

func (s *Service) LabelMetadataWithChecks(ctx context.Context, labelable github.Labelable, actors sweagentd.RepositoryWithActor) sweagentd.LabelMetadata {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.LabelMetadataWithChecks")
	defer span.End()

	return LabelMetadataWithChecks(ctx, s.ffs, actors, labelable.GetLabels().Nodes)
}

func LabelMetadataForJob(ctx context.Context, ffs featureflags.Client, actors sweagentd.RepositoryWithActor, labelable github.Labelable) sweagentd.LabelMetadata {
	return LabelMetadataWithChecks(ctx, ffs, actors, labelable.GetLabels().Nodes)
}

func LabelMetadataWithChecks[E interface{ GetName() string }](ctx context.Context, ffs featureflags.Client, actors sweagentd.RepositoryWithActor, labels []E) sweagentd.LabelMetadata {
	labelNames := make([]string, 0, len(labels))
	for _, label := range labels {
		labelNames = append(labelNames, label.GetName())
	}

	return labelMetadataWithChecks(ctx, ffs, actors, labelNames)
}

func labelMetadataWithChecks(ctx context.Context, ffs featureflags.Client, actors sweagentd.RepositoryWithActor, labels []string) sweagentd.LabelMetadata {
	var m sweagentd.LabelMetadata

	canSelectModel := ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCanSelectModel, actors)

	for _, name := range labels {
		if strings.HasPrefix(name, sweagentd.CopilotLabelPrefix) {
			if canSelectModel {
				if model, ok := strings.CutPrefix(name, sweagentd.ModelLabelPrefix); ok {
					m.Model = model
				}
			}

			m.CopilotLabels = append(m.CopilotLabels, name)
		}

		m.Labels = append(m.Labels, name)
	}

	return m
}
