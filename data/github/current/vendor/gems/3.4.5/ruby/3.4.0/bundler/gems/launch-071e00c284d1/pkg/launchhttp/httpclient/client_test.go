package httpclient

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strconv"
	"testing"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/pkg/launchhttp/httpmock"
)

var testClientOpts = func(o *ClientOptions) {
	o.ReqRetryDelay = 1 * time.Millisecond
	o.ReqRetryMultiplier = 0.0
	o.ReqRetryRandFactor = 0.0
	o.ReqMaxRetries = 3
}

type testDst struct {
	Value string `json:"value"`
}

func TestClient_Do(t *testing.T) {
	type args struct {
		dst  any
		body any
		opts []DoOption
	}

	testValidator := func(res *http.Response) (retryable bool, err error) {
		if res.StatusCode == http.StatusOK {
			return false, nil
		}

		if res.StatusCode >= http.StatusBadRequest && res.StatusCode < 500 {
			return false, backoff.Permanent(fmt.Errorf("permanent"))
		}

		return true, fmt.Errorf("temporary")
	}

	tests := []struct {
		name     string
		args     args
		wantErr  bool
		handlerF http.HandlerFunc
		wantDst  any
	}{
		{
			name: "happy path, no dst",
			handlerF: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				fmt.Fprintln(w, "Hello, client")
			}),
			wantErr: false,
			args: args{
				dst:  nil,
				opts: nil,
			},
		},
		{
			name: "happy path, dst",
			handlerF: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				json.NewEncoder(w).Encode(testDst{Value: "hello"})
			}),
			wantErr: false,
			wantDst: &testDst{Value: "hello"},
			args: args{
				dst:  &testDst{},
				opts: nil,
			},
		},
		{
			name: "fails",
			handlerF: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				http.Error(w, "", 500)
			}),
			wantErr: true,
			args: args{
				dst:  nil,
				opts: nil,
			},
		},
		{
			name: "doesn't retry if not asked to retry",
			handlerF: func() http.HandlerFunc {
				counter := 0
				return func(w http.ResponseWriter, _ *http.Request) {
					if counter == 0 {
						http.Error(w, "", 500)
						counter++
						return
					}
					t.Errorf("should not have retried")
				}
			}(),
			wantErr: true,
			args: args{
				dst: &testDst{},
			},
		},
		{
			name: "retries 1",
			handlerF: func() http.HandlerFunc {
				counter := 0
				return func(w http.ResponseWriter, _ *http.Request) {
					if counter < 1 {
						http.Error(w, "", 500)
					}
					json.NewEncoder(w).Encode(testDst{Value: strconv.Itoa(counter)})
					counter++
				}
			}(),
			wantErr: false,
			wantDst: &testDst{Value: "1"},
			args: args{
				dst:  &testDst{},
				opts: []DoOption{WithRetries(testValidator)},
			},
		},
		{
			name: "retries 2",
			handlerF: func() http.HandlerFunc {
				counter := 0
				return func(w http.ResponseWriter, _ *http.Request) {
					if counter < 2 {
						http.Error(w, "", 500)
					}
					json.NewEncoder(w).Encode(testDst{Value: strconv.Itoa(counter)})
					counter++
				}
			}(),
			wantErr: false,
			wantDst: &testDst{Value: "2"},
			args: args{
				dst:  &testDst{},
				opts: []DoOption{WithRetries(testValidator)},
			},
		},
		{
			name: "retries 3",
			handlerF: func() http.HandlerFunc {
				counter := 0
				return func(w http.ResponseWriter, _ *http.Request) {
					if counter < 3 {
						http.Error(w, "", 500)
					}
					json.NewEncoder(w).Encode(testDst{Value: strconv.Itoa(counter)})
					counter++
				}
			}(),
			wantErr: false,
			wantDst: &testDst{Value: "3"},
			args: args{
				dst:  &testDst{},
				opts: []DoOption{WithRetries(testValidator)},
			},
		},
		{
			name: "retries exhausted",
			handlerF: func() http.HandlerFunc {
				counter := 0
				return func(w http.ResponseWriter, _ *http.Request) {
					if counter < 4 {
						http.Error(w, "", 500)
					}
					json.NewEncoder(w).Encode(testDst{Value: strconv.Itoa(counter)})
					counter++
				}
			}(),
			wantErr: true,
			args: args{
				dst:  &testDst{},
				opts: []DoOption{WithRetries(testValidator)},
			},
		},
		{
			name: "retries with backoff",
			handlerF: func() http.HandlerFunc {
				counter := 0
				return func(w http.ResponseWriter, _ *http.Request) {
					if counter < 3 {
						http.Error(w, "", 500)
					}
					t.Logf("call: %d | time: %v", counter, time.Now())
					json.NewEncoder(w).Encode(testDst{Value: strconv.Itoa(counter)})
					counter++
				}
			}(),
			wantErr: false,
			wantDst: &testDst{Value: "3"},
			args: args{
				dst: &testDst{},
				opts: []DoOption{
					WithBackoff(
						3,
						100*time.Millisecond,
						2,
						0.5,
					),
				},
			},
		},
		{
			name: "with inspector",
			handlerF: func() http.HandlerFunc {
				counter := 0
				return func(w http.ResponseWriter, _ *http.Request) {
					if counter < 4 {
						http.Error(w, "", 500)
					}
					json.NewEncoder(w).Encode(testDst{Value: strconv.Itoa(counter)})
					counter++
				}
			}(),
			wantErr: true,
			args: args{
				dst: &testDst{},
				opts: []DoOption{WithRetries(testValidator), func(do *DoOptions) {
					do.ResponseInspector = func(v any) (bool, error) {
						dst, ok := v.(testDst)
						if !ok {
							return false, backoff.Permanent(errors.New("wrong type"))
						}

						if dst.Value != "4" {
							return false, nil
						} else {
							return true, nil
						}
					}
				}},
			},
		},
		{
			name: "bodybuilder is built on each operation attempt",
			handlerF: func() http.HandlerFunc {
				previousCounter := -1
				return func(w http.ResponseWriter, r *http.Request) {
					bs, err := io.ReadAll(r.Body)
					if err != nil {
						panic(err)
					}

					var b byte
					err = binary.Read(bytes.NewReader(bs), binary.BigEndian, &b)
					if err != nil {
						panic(err)
					}

					counter := int(b)

					if counter <= previousCounter {
						http.Error(w, "counter should be incrementing", 400)
					}

					if counter > 1 {
						// Now we know we're incrementing each operation, nice!
						fmt.Fprint(w, "it worked")
					}

					previousCounter = counter

					if counter <= previousCounter {
						http.Error(w, "we need to see another attempt", 503)
					}
				}
			}(),
			args: args{
				body: func() BodyBuilder {
					counter := 0
					return func() (io.Reader, error) {
						r := bytes.NewReader([]byte{byte(counter)})
						counter++
						return r, nil
					}
				}(),
				opts: []DoOption{WithRetries(testValidator), func(do *DoOptions) {}},
			},
		},
	}
	t.Parallel()
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(tt.handlerF)

			ctx := context.Background()

			c := New(ts.Client(), testClientOpts)
			if err := c.Do(ctx, tt.name, http.MethodGet, ts.URL, tt.args.body, tt.args.dst, tt.args.opts...); (err != nil) != tt.wantErr {
				t.Errorf("Client.Do() error = %v, wantErr %v", err, tt.wantErr)
			}
			if tt.wantDst != nil && !reflect.DeepEqual(tt.wantDst, tt.args.dst) {
				t.Errorf("Client.Do() dst = %v, wantDst %v", tt.args.dst, tt.wantDst)
			}
		})
	}
}

func TestClient_DoURLBuilder(t *testing.T) {
	tests := []struct {
		name       string
		wantErr    bool
		handlerF   http.HandlerFunc
		urlBuilder func(url string) URLBuilder
	}{
		{
			name: "Succeeds when URLBuilder does not return error",
			handlerF: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				fmt.Fprintln(w, "Hello, client")
			}),
			wantErr: false,
			urlBuilder: func(url string) URLBuilder {
				return func() (string, error) {
					return url, nil
				}
			},
		},
		{
			name: "Returns error when URLBuilder returns error",
			handlerF: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				fmt.Fprintln(w, "Hello, client")
			}),
			wantErr: true,
			urlBuilder: func(url string) URLBuilder {
				return func() (string, error) {
					return "", errors.New("error")
				}
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(tt.handlerF)

			ctx := context.Background()

			c := New(ts.Client(), testClientOpts)

			if err := c.DoWithURLBuilder(ctx, tt.name, http.MethodGet, tt.urlBuilder(ts.URL), nil, nil, nil...); (err != nil) != tt.wantErr {
				t.Errorf("Client.Do() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestClient_Do_MockedHTTP(t *testing.T) {
	type args struct {
		opts []DoOption
	}

	tests := []struct {
		name    string
		args    args
		wantErr bool
		doneCtx bool
		mocker  func(*httpmock.Client)
	}{
		{
			name: "happy",
			mocker: func(c *httpmock.Client) {
				c.EXPECT().Do(mock.Anything).Return(&http.Response{StatusCode: 200}, nil)
			},
		},
		{
			name: "error",
			mocker: func(c *httpmock.Client) {
				c.EXPECT().Do(mock.Anything).Return(nil, io.EOF)
			},
			wantErr: true,
		},
		{
			name:    "context is done",
			mocker:  func(c *httpmock.Client) {},
			doneCtx: true,
			wantErr: true,
		},
	}
	t.Parallel()
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			backend := httpmock.NewClient(t)

			ctx := context.Background()

			if tt.doneCtx {
				var cancelFunc context.CancelFunc
				ctx, cancelFunc = context.WithCancel(ctx)
				cancelFunc()
			}

			tt.mocker(backend)

			c := New(backend, testClientOpts)

			err := c.Do(ctx, tt.name, http.MethodGet, "", nil, nil, tt.args.opts...)
			require.Equal(t, tt.wantErr, err != nil)
		})
	}
}
