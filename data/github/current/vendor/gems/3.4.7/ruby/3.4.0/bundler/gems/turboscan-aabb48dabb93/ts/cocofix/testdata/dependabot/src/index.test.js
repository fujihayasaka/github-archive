const fetchData = require('./index');
const axios = require('axios');
jest.mock('axios');

test('fetchData fetches successfully data from an API', async () => {
  const data = { data: { key: 'value' } };
  axios.get.mockResolvedValue(data);

  const result = await fetchData();
  expect(result).toEqual({ key: 'value' });
});

test('fetchData returns null when API call fails', async () => {
  axios.get.mockRejectedValue(new Error('API call failed'));

  const result = await fetchData();
  expect(result).toBeNull();
});
