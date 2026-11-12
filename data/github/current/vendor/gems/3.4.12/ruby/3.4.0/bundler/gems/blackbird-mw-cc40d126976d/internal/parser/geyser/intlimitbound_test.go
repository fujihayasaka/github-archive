package geyser

import (
	"reflect"
	"testing"
)

func TestIntLimitBound_String(t *testing.T) {
	tests := []struct {
		name   string
		fields IntLimitBound
		want   string
	}{
		{
			name:   "test1",
			fields: IntLimitBound{0, false, false},
			want:   ">0",
		},
		{
			name:   "test2",
			fields: IntLimitBound{-24, true, false},
			want:   ">=-24",
		},
		{
			name:   "test3",
			fields: IntLimitBound{13, false, true},
			want:   "<13",
		},
		{
			name:   "test4",
			fields: IntLimitBound{42, true, true},
			want:   "<=42",
		},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.fields.String(); got != tt.want {
				t.Errorf("String() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestNewIntLimitBoundFromString(t *testing.T) {
	tests := []struct {
		name    string
		args    string
		want    *IntLimitBound
		wantErr bool
	}{
		{
			name:    "test1",
			args:    "<=42",
			want:    &IntLimitBound{42, true, true},
			wantErr: false,
		},
		{
			name:    "test2",
			args:    ">=42",
			want:    &IntLimitBound{42, true, false},
			wantErr: false,
		},
		{
			name:    "test3",
			args:    "<42",
			want:    &IntLimitBound{42, false, true},
			wantErr: false,
		},
		{
			name:    "test4",
			args:    ">42",
			want:    &IntLimitBound{42, false, false},
			wantErr: false,
		},
		{
			name:    "invalid prefix",
			args:    "=42",
			wantErr: true,
		},
		{
			name:    "invalid number parsed",
			args:    "<a42",
			wantErr: true,
		},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			got, err := NewIntLimitBoundFromString(tt.args)
			if (err != nil) != tt.wantErr {
				t.Errorf("NewIntLimitBoundFromString() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("NewIntLimitBoundFromString() got = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestNewIntLimitBound(t *testing.T) {
	tests := []struct {
		name    string
		want    string
		wantErr bool
	}{
		{
			name:    "test1",
			want:    "<42",
			wantErr: false,
		},
		{
			name:    "test2",
			want:    "<=42",
			wantErr: false,
		},
		{
			name:    "test3",
			want:    ">42",
			wantErr: false,
		},
		{
			name:    "test4",
			want:    ">=42",
			wantErr: false,
		},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			ibl, err := NewIntLimitBoundFromString(tt.want)
			if (err != nil) != tt.wantErr {
				t.Errorf("IntLimitBound.String() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			got := ibl.String()
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("IntLimitBound.String() got = %v, want %v", got, tt.want)
			}
		})
	}
}
