// Package datastructures contains internal email data structures.
package datastructures

import (
	"time"

	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"

	v0 "github.com/github/notifyd/hydro/schemas/notifyd/v0"
)

// Email is the internal Notifyd datastructure of an email
// any proto message is converted into this model
// and only this model is passed around between service and storage layers
type Email struct {
	OrganizationID int64
	UserID         int64
	NotificationID string
	SubjectType    string
	LayoutData     *anypb.Any
	MatchData      *structpb.Struct
	Reasons        []string
	Tracking       *Tracking
	Retries        Retries
}

// Tracking contains data used for tracking events through the whole system
type Tracking struct {
	TriggeredAt     time.Time
	SubjectMetadata *SubjectMetadata
}

// SubjectMetadata contains data about the subject of the email
type SubjectMetadata struct {
	ListType    string
	ListID      string
	ThreadType  string
	ThreadID    string
	CommentType string
	CommentID   string
}

// Retries records the number of attempts to deliver the email
type Retries struct {
	Attempts int
}

// EmailFromV0 converts a v0.DeliverEmail message into an Email
func EmailFromV0(msg *v0.DeliverEmail) *Email {
	var reasons []string
	for _, r := range msg.Reasons {
		reasons = append(reasons, r.GetName())
	}

	var matchdata structpb.Struct
	if msg.MatchData != nil {
		err := anypb.UnmarshalTo(msg.MatchData, &matchdata, proto.UnmarshalOptions{})
		if err != nil {
			return nil
		}
	}

	var retries Retries
	if msg.Retries != nil {
		retries.Attempts = int(msg.Retries.Attempts)
	}

	e := &Email{
		OrganizationID: msg.GetOrganizationId().GetValue(),
		UserID:         int64(msg.UserId),
		NotificationID: msg.NotificationId,
		SubjectType:    msg.GetSubjectType(),
		LayoutData:     msg.GetLayoutData(),
		MatchData:      &matchdata,
		Reasons:        reasons,
		Retries:        retries,
	}

	if msg.Tracking != nil {
		e.Tracking = &Tracking{TriggeredAt: msg.Tracking.GetTriggeredAt().AsTime()}
		if msg.Tracking.SubjectMetadata != nil {
			e.Tracking.SubjectMetadata = &SubjectMetadata{
				ListType:    msg.Tracking.SubjectMetadata.ListType,
				ListID:      msg.Tracking.SubjectMetadata.ListId,
				ThreadType:  msg.Tracking.SubjectMetadata.ThreadType,
				ThreadID:    msg.Tracking.SubjectMetadata.ThreadId,
				CommentType: msg.Tracking.SubjectMetadata.CommentType,
				CommentID:   msg.Tracking.SubjectMetadata.CommentId,
			}
		}
	}

	return e
}
