package geyser

import (
	"reflect"
	"testing"
)

func TestIntRange_String(t *testing.T) {
	tests := []struct {
		name   string
		fields IntRange
		want   string
	}{
		{
			name: "test1",
			fields: IntRange{
				UpperLimit: nil,
				LowerLimit: nil,
			},
			want: "*..*",
		},
		{
			name: "half closed prints as limit boundary",
			fields: IntRange{
				UpperLimit: mustIntLimitBound("<=42"),
				LowerLimit: nil,
			},
			want: "<=42",
		},
		{
			name: "half open prints as limit boundary",
			fields: IntRange{
				UpperLimit: nil,
				LowerLimit: mustIntLimitBound(">0"),
			},
			want: ">0",
		},
		{
			name: "full interval prints using dot syntax",
			fields: IntRange{
				UpperLimit: mustIntLimitBound("<100"),
				LowerLimit: mustIntLimitBound(">42"),
			},
			want: "42..100",
		},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			ir := IntRange{
				UpperLimit: tt.fields.UpperLimit,
				LowerLimit: tt.fields.LowerLimit,
			}
			if got := ir.String(); got != tt.want {
				t.Errorf("String() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestNewIntRangeFromString(t *testing.T) {
	tests := []struct {
		name    string
		text    string
		want    *IntRange
		wantErr bool
	}{
		{
			name: "bounded",
			text: "42..100",
			want: &IntRange{
				UpperLimit: mustIntLimitBound("<=100"),
				LowerLimit: mustIntLimitBound(">=42"),
			},
			wantErr: false,
		},
		{
			name: "lower half bounded",
			text: "42..*",
			want: &IntRange{
				UpperLimit: nil,
				LowerLimit: mustIntLimitBound(">=42"),
			},
			wantErr: false,
		},
		{
			name: "upper half bounded",
			text: "*..100",
			want: &IntRange{
				UpperLimit: mustIntLimitBound("<=100"),
				LowerLimit: nil,
			},
			wantErr: false,
		},
		{
			name: "as upper boundary limit",
			text: "<100",
			want: &IntRange{
				UpperLimit: mustIntLimitBound("<100"),
				LowerLimit: nil,
			},
			wantErr: false,
		},
		{
			name: "as lower boundary limit",
			text: ">100",
			want: &IntRange{
				UpperLimit: nil,
				LowerLimit: mustIntLimitBound(">100"),
			},
			wantErr: false,
		},
		{
			name:    "invalid interval",
			text:    "..100",
			wantErr: true,
		},
		{
			name:    "invalid interval 2",
			text:    "100",
			wantErr: true,
		},
		{
			name:    "invalid interval 3",
			text:    "100..42",
			wantErr: true,
		},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			got, err := NewIntRangeFromString(tt.text)
			if (err != nil) != tt.wantErr {
				t.Errorf("NewIntRangeFromString() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("NewIntRangeFromString() got = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestNewIntRange(t *testing.T) {
	type args struct {
		lower *IntLimitBound
		upper *IntLimitBound
	}
	tests := []struct {
		name    string
		args    args
		wantErr bool
	}{
		{
			name: "both the same",
			args: args{
				lower: mustIntLimitBound(">0"),
				upper: mustIntLimitBound(">0"),
			},
			wantErr: true,
		},
		{
			name: "mismatched directions",
			args: args{
				lower: mustIntLimitBound(">0"),
				upper: mustIntLimitBound("<0"),
			},
			wantErr: true,
		},
		{
			name: "invalid boundaries",
			args: args{
				lower: mustIntLimitBound(">=0"),
				upper: mustIntLimitBound("<0"),
			},
			wantErr: true,
		},
		{
			name: "invalid boundaries 2",
			args: args{
				lower: mustIntLimitBound(">0"),
				upper: mustIntLimitBound("<=0"),
			},
			wantErr: true,
		},
		{
			name: "valid single point boundaries",
			args: args{
				lower: mustIntLimitBound(">=0"),
				upper: mustIntLimitBound("<=0"),
			},
			wantErr: false,
		},
		{
			name: "valid single point boundaries",
			args: args{
				lower: mustIntLimitBound(">0"),
				upper: mustIntLimitBound("<1"),
			},
			wantErr: false,
		},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			_, err := NewIntRange(tt.args.lower, tt.args.upper)
			if (err != nil) != tt.wantErr {
				t.Errorf("NewIntRange() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
		})
	}
}
