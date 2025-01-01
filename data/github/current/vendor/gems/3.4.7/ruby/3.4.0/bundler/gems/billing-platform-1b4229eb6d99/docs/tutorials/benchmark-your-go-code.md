# Benchmark your Go Code

Make Go go fast.

Benchmarks can be used to measure how long a test takes to run, allowing you to identify bottlenecks in your code.

## Table of Contents

- [Terminology](#terminology)
- [Details](#details)
  - [What is a Benchmark](#what-is-a-benchmark)
  - [How do you set up a Benchmark](#how-do-you-set-up-a-benchmark)
  - [How do you interpret a Benchmark](#how-do-you-interpret-a-benchmark)
- [References](#references)

## Terminology

- **Benchmarks**: Measure how long it takes to run tests, and thus the performance of code.

## Details

### What is a Benchmark

Benchmarks in Go are utilized to measure the performance of code by running it repeatedly and calculating the average time taken for execution. This helps to understand the efficiency of the code and to help identify potential areas for improvement.

### How do you set up a Benchmark

You can easily use existing Go tests to set up Benchmarks (and this is a great reason for writing more unit tests!). Here is an example Benchmark test using tests from `usageChartData_test.go`:

```golang
// The test
func Test_getGroupString(t *testing.T) {
	item := &models.UsageItem{
		UsageEntityId:   "123",
		Product:         "product1",
		Sku:             "sku1",
		UsageAt:         1722378113028,
		GrossAmount:     100.0,
		DiscountAmount:  10.0,
		NetAmount:       90.0,
		FriendlySkuName: "friendlySkuName",
		RepoId:          12,
		OrgId:           10,
	}

	tests := []struct {
		name     string
		groupBy  proto.UsageGroupBy
		expected string
	}{
		{"NoGroupBy", proto.UsageGroupBy_NoGroupBy, "Usage"},
		{"GroupByProduct", proto.UsageGroupBy_GroupByProduct, "product1"},
		{"GroupBySku", proto.UsageGroupBy_GroupBySku, "friendlySkuName"},
		{"GroupByOrganization", proto.UsageGroupBy_GroupByOrganization, "10"},
		{"GroupByRepository", proto.UsageGroupBy_GroupByRepository, "12"},
		{"GroupByOrgRepoProductSku", proto.UsageGroupBy_GroupByOrgRepoProductSku, "10-12-product1-sku1"},
		{"GroupByCostCenter", proto.UsageGroupBy_GroupByCostCenter, "123"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			groupString := getGroupString(tt.groupBy, item)
			assert.Equal(t, tt.expected, groupString)
		})
	}
}


// The Benchmark for the test
func Benchmark_getGroupString(b *testing.B) {
	item := &models.UsageItem{
		UsageEntityId:   "123",
		Product:         "product1",
		Sku:             "sku1",
		UsageAt:         1722378113028,
		GrossAmount:     100.0,
		DiscountAmount:  10.0,
		NetAmount:       90.0,
		FriendlySkuName: "friendlySkuName",
		RepoId:          12,
		OrgId:           10,
	}

	benchmarks := []struct {
		name    string
		groupBy proto.UsageGroupBy
	}{
		{"NoGroupBy", proto.UsageGroupBy_NoGroupBy},
		{"GroupByProduct", proto.UsageGroupBy_GroupByProduct},
		{"GroupBySku", proto.UsageGroupBy_GroupBySku},
		{"GroupByOrganization", proto.UsageGroupBy_GroupByOrganization},
		{"GroupByRepository", proto.UsageGroupBy_GroupByRepository},
		{"GroupByOrgRepoProductSku", proto.UsageGroupBy_GroupByOrgRepoProductSku},
		{"GroupByCostCenter", proto.UsageGroupBy_GroupByCostCenter},
	}

	for _, bm := range benchmarks {
		b.Run(bm.name, func(b *testing.B) {
			for i := 0; i < b.N; i++ {
				getGroupString(bm.groupBy, item)
			}
		})
	}
}
```

> [!NOTE]
> Copilot is super good at quickly generating Benchmarks! Highlight a particular unit test that you would like to Benchmark and ask Copilot to modify it to `Write a Benchmark for these tests`.

You can run the Benchmark above by running `go test -bench=.`, to run all of the Benchmarks in tests in the application.

There may be some good reasons to commit Benchmark tests to this repo, however I will likely avoid doing that for now to avoid adding any extra overhead to our tests.

### How do you interpret a Benchmark

Here is an example output from running the Benchmark above:

```bash
Benchmark_getGroupString
Benchmark_getGroupString/NoGroupBy
Benchmark_getGroupString/NoGroupBy-16         	641924276	         1.857 ns/op	       0 B/op	       0 allocs/op
Benchmark_getGroupString/GroupByProduct
Benchmark_getGroupString/GroupByProduct-16    	551065909	         2.173 ns/op	       0 B/op	       0 allocs/op
Benchmark_getGroupString/GroupBySku
Benchmark_getGroupString/GroupBySku-16        	537203205	         2.189 ns/op	       0 B/op	       0 allocs/op
Benchmark_getGroupString/GroupByOrganization
Benchmark_getGroupString/GroupByOrganization-16         	17212407	        69.72 ns/op	       2 B/op	       1 allocs/op
Benchmark_getGroupString/GroupByRepository
Benchmark_getGroupString/GroupByRepository-16           	17179356	        69.85 ns/op	       2 B/op	       1 allocs/op
Benchmark_getGroupString/GroupByOrgRepoProductSku
Benchmark_getGroupString/GroupByOrgRepoProductSku-16    	 5520186	       215.3 ns/op	      56 B/op	       3 allocs/op
Benchmark_getGroupString/GroupByCostCenter
Benchmark_getGroupString/GroupByCostCenter-16           	482545461	         2.524 ns/op	       0 B/op	       0 allocs/op
```

Each run has the following:

1. **Benchmark Name**: Each benchmark has a name, typically starting with Benchmark_. In this case, it's Benchmark_getGroupString with various subtests for different groupings.
2. **Subtest Names**: The benchmark contains subtests, each testing a different scenario or variation. For example, NoGroupBy, GroupByProduct, GroupBySku, etc.
3. **CPU Count**: The number following the subtest name (e.g., -16) indicates the number CPUs used to run the tests.
4. **Number of Operations**: The first number after the subtest name indicates how many times the benchmarked code was run per iteration. For example, 641924276 means the code was executed 641,924,276 times in that subtest.
5. **Time per Operation**: The value with ns/op indicates the average time taken per operation in nanoseconds. For example, 1.857 ns/op means each operation took 1.857 nanoseconds on average.
6. **Allocated Bytes per Operation**: The value with B/op indicates the number of bytes allocated per operation. For example, 0 B/op means no memory allocation occurred per operation.
7. **Allocations per Operation**: The value with allocs/op indicates the number of memory allocations per operation. For example, 0 allocs/op means no memory allocations occurred per operation.

In the example output provided, we can see that the `GroupByOrgRepoProductSku` output is the slowest and most memory-intensive subtest. This helps us identify where to improve the code that is being tested!

## References

- [Benchmark testing in Go](https://dev.to/stefanalfbo/benchmark-testing-in-go-17dc)
- [Go by Example: Testing and Benchmarking](https://gobyexample.com/testing-and-benchmarking)
