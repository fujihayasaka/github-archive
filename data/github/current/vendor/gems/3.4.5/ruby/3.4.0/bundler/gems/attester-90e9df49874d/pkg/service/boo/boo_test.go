package boo

import (
	"testing"
)

func TestName(_ *testing.T) {
	// ctx := context.Background()
	// ctrl := gomock.NewController(t)
	// telem, err := telemetry.NewFromEnv()
	// if err != nil {
	// 	fmt.Printf("Failed configuring telemetry: %v", err)
	// 	t.FailNow()
	// }

	// name := "Albus Dumbledore"
	// mockWordSvc := mocks.NewMockWordService(ctrl)
	// testServer := &Server{
	// 	wordSvc: mockWordSvc,
	// 	telem:   telem,
	// }

	// req := &proto.NameRequest{
	// 	Name: name,
	// }

	// res, err := testServer.HelloName(ctx, req)
	// tu.Ok(t, err)

	// expected := fmt.Sprintf("Hello, %v!", name)
	// tu.Equals(t, expected, res.GetMessage())
}

func TestReverseName(_ *testing.T) {
	// ctx := context.Background()
	// ctrl := gomock.NewController(t)
	// telem, err := telemetry.NewFromEnv()
	// if err != nil {
	// 	fmt.Printf("Failed configuring telemetry: %v", err)
	// 	t.FailNow()
	// }

	// name := "Albus Dumbledore"
	// reversedName := "erodelbmuD sublA"
	// mockWordSvc := mocks.NewMockWordService(ctrl)
	// mockWordSvc.EXPECT().ReverseWord(&pkg.Word{
	// 	Name: name,
	// }).Return(&pkg.Word{
	// 	Name: reversedName,
	// }, nil)
	// testServer := &Server{
	// 	wordSvc: mockWordSvc,
	// 	telem:   telem,
	// }

	// req := &proto.NameRequest{
	// 	Name: name,
	// }

	// res, err := testServer.ReverseName(ctx, req)
	// tu.Ok(t, err)
	// tu.Equals(t, reversedName, res.GetMessage())
}
