package common

import (
	"context"
	"reflect"
	"testing"

	"github.com/golang/mock/gomock"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
)

type retryTestMock struct {
	ctrl     *gomock.Controller
	recorder *retryTestMockRecorder
}
type retryTestMockRecorder struct {
	mock *retryTestMock
}

func NewRetryTestMock(ctrl *gomock.Controller) *retryTestMock {
	mock := &retryTestMock{ctrl: ctrl}
	mock.recorder = &retryTestMockRecorder{mock}
	return mock
}
func (m *retryTestMock) EXPECT() *retryTestMockRecorder {
	return m.recorder
}
func (m *retryTestMock) TestFunction(arg0 context.Context) error {
	m.ctrl.T.Helper()
	ret := m.ctrl.Call(m, "TestFunction")
	ret0, _ := ret[0].(error)
	return ret0
}
func (mr *retryTestMockRecorder) TestFunction(arg0 interface{}) *gomock.Call {
	mr.mock.ctrl.T.Helper()
	return mr.mock.ctrl.RecordCallWithMethodType(mr.mock, "TestFunction", reflect.TypeOf((*retryTestMock)(nil).TestFunction))
}
func (m *retryTestMock) TestFunctionWithBool(arg0 context.Context) (bool, error) {
	m.ctrl.T.Helper()
	ret := m.ctrl.Call(m, "TestFunctionWithBool")
	ret0, _ := ret[0].(bool)
	ret1, _ := ret[1].(error)
	return ret0, ret1
}
func (mr *retryTestMockRecorder) TestFunctionWithBool(arg0 interface{}) *gomock.Call {
	mr.mock.ctrl.T.Helper()
	return mr.mock.ctrl.RecordCallWithMethodType(mr.mock, "TestFunctionWithBool", reflect.TypeOf((*retryTestMock)(nil).TestFunctionWithBool))
}

func TestWithRetriesZeroTimesSuccess(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)

	mockedFunctions.EXPECT().TestFunction(gomock.Any()).Times(1)

	err := WithRetries(
		context.Background(),
		"test_function",
		mockedFunctions.TestFunction,
		0,
	)
	require.NoError(t, err)
}

func TestWithRetriesZeroTimesNonRetryableError(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	expectedErr := errors.New("test_error")

	mockedFunctions.EXPECT().TestFunction(gomock.Any()).Times(1).Return(expectedErr)

	err := WithRetries(
		context.Background(),
		"test_function",
		mockedFunctions.TestFunction,
		0,
	)
	require.ErrorIs(t, err, expectedErr)
}

func TestWithRetriesZeroTimesRetryableError(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	retryableErr := errors.New("test_error")

	mockedFunctions.EXPECT().TestFunction(gomock.Any()).Times(1).Return(retryableErr)

	err := WithRetries(
		context.Background(),
		"test_function",
		mockedFunctions.TestFunction,
		0,
		retryableErr,
	)
	require.EqualError(t, err, retryableErr.Error())
}

func TestWithRetriesWithBoolZeroTimesSuccess(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	expectedResponse := true

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(1).Return(expectedResponse, nil)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		0,
	)

	require.NoError(t, err)
	require.Equal(t, expectedResponse, response)
}

func TestWithRetriesWithBoolZeroTimesRetryableError(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	expectedResponse := false
	retryableErr := errors.New("test_error")

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(1).Return(expectedResponse, retryableErr)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		0,
		retryableErr,
	)

	require.EqualError(t, err, retryableErr.Error())
	require.Equal(t, expectedResponse, response)
}

func TestWithRetriesWithBoolOneRetryWithRetryableError(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	retryableErr := errors.New("some_error_message")

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(2).Return(false, retryableErr)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		1,
		retryableErr,
	)

	require.EqualError(t, err, retryableErr.Error())
	require.Equal(t, false, response)
}

func TestWithRetriesWithBoolOneRetryWithRetryableErrorSuccessOnRetry(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	retryableErr := errors.New("some_error_message")

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(1).Return(false, retryableErr)
	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(1).Return(true, nil)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		1,
		retryableErr,
	)

	require.NoError(t, err)
	require.Equal(t, true, response)
}

func TestWithRetriesWithBoolOneRetryNonRetryable(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	nonRetryableErr := errors.New("non_retryable")

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(1).Return(false, nonRetryableErr)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		1,
		errors.New("retryable"),
	)

	require.ErrorIs(t, err, nonRetryableErr)
	require.Equal(t, false, response)
}

func TestWithRetriesWithBoolOneRetrySuccessOnFirst(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	expectedResponse := true

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(1).Return(expectedResponse, nil)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		1,
		errors.New("any_retryable_error"),
		errors.New("another_retryable_error"),
	)

	require.NoError(t, err)
	require.Equal(t, expectedResponse, response)
}

func TestWithRetriesWithBoolOneRetrySuccessOnRetry(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	expectedResponse := true
	firstFailureAsRetryable := errors.New("as_retryable")

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Return(false, firstFailureAsRetryable)
	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Return(expectedResponse, nil)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		1,
		firstFailureAsRetryable,
		errors.New("another_retryable_error"),
	)

	require.NoError(t, err)
	require.Equal(t, expectedResponse, response)
}

func TestWithRetriesWithBoolThreeRetriesFirstSuccess(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(1).Return(true, nil)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		3,
	)

	require.NoError(t, err)
	require.Equal(t, true, response)
}

func TestWithRetriesWithBoolThreeRetriesFirstErrorNonRetryable(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	nonRetryableError := errors.New("non_retryable_error_msg")

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(1).Return(false, nonRetryableError)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		3,
		errors.New("some_retryable_not_for_this_test"),
	)

	require.ErrorIs(t, err, nonRetryableError)
	require.Equal(t, false, response)
}

func TestWithRetriesWithBoolThreeRetriesFirstErrorRetryableSecondNonRetryable(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	firstErrorRetryable := errors.New("retryable_err")
	secondErrorNonRetryable := errors.New("non_retryable_error_msg")

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Return(false, firstErrorRetryable)
	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Return(false, secondErrorNonRetryable)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		3,
		firstErrorRetryable,
		errors.New("some_retryable_not_for_this_test"),
	)

	require.ErrorIs(t, err, secondErrorNonRetryable)
	require.Equal(t, false, response)
}

func TestWithRetriesWithBoolThreeRetriesFirstThreeErrorsRetryableFourthAttemptSuccess(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	errorRetryable := errors.New("retryable_err")
	expectedResponse := true

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(3).Return(false, errorRetryable)
	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Return(expectedResponse, nil)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		3,
		errorRetryable,
		errors.New("some_retryable_not_for_this_test"),
	)

	require.NoError(t, err)
	require.Equal(t, expectedResponse, response)
}

func TestWithRetriesWithBoolThreeRetriesDifferentRetryableErrors(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	errorRetryable1 := errors.New("retryable_err_1")
	errorRetryable2 := errors.New("retryable_err_2")

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(3).Return(false, errorRetryable1)
	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(1).Return(false, errorRetryable2)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		3,
		errorRetryable1,
		errorRetryable2,
	)

	// returns the last error seen
	require.EqualError(t, err, errorRetryable2.Error())
	require.Equal(t, false, response)
}

func TestWithWrappedRetryableError(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	retryableError := errors.New("retryable_err")
	wrappedRetryableError := errors.Wrap(retryableError, "Im a rapper")
	expectedResponse := true

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(1).Return(false, wrappedRetryableError)
	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Return(expectedResponse, nil)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		1,
		retryableError,
		errors.New("some_retryable_not_for_this_test"),
	)

	require.NoError(t, err)
	require.Equal(t, expectedResponse, response)
}

func TestContextCanceledErrorNoRetry(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	contextCanceledErr := context.Canceled

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Times(1).Return(false, contextCanceledErr)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		5,
		context.Canceled,
	)

	require.Error(t, err)
	require.ErrorIs(t, context.Canceled, err)
	require.Equal(t, false, response)
}

func TestWithRetriesNoDefinedRetryableErrors(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockedFunctions := NewRetryTestMock(ctrl)
	lastErr := errors.New("last_retry_err")

	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Return(false, errors.New("first_err"))
	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Return(false, errors.New("retry_err_1"))
	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Return(false, errors.New("retry_err_2"))
	mockedFunctions.EXPECT().TestFunctionWithBool(gomock.Any()).Return(false, lastErr)

	var response bool
	err := WithRetries(
		context.Background(),
		"test_function_with_bool",
		func(operationCtx context.Context) error {
			resp, err := mockedFunctions.TestFunctionWithBool(operationCtx)
			response = resp
			return err
		},
		3,
	)

	require.ErrorIs(t, err, lastErr)
	require.Equal(t, false, response)
}
