test_that("success request returns response", {
  resp <- request_test() %>% req_perform()
  expect_s3_class(resp, "httr2_response")
})

test_that("curl and http errors become errors", {
  req <- request_test("/delay/:secs", secs = 1) %>% req_timeout(0.1)
  expect_error(req_perform(req), class = "httr2_failed")

  req <- request_test("/status/:status", status = 404)
  expect_snapshot(
    (expect_error(req_perform(req), class = "httr2_http_404"))
  )

  # including transient errors
  req <- request_test("/status/:status", status = 429)
  expect_snapshot(req_perform(req), error = TRUE)

  req_perform(req) %>%
    expect_error(class = "httr2_http_429") %>%
    expect_no_condition(class = "httr2_sleep")
})

test_that("can force successful HTTP statuses to error", {
  req <- request_test("/status/:status", status = 200) %>%
    req_error(is_error = function(resp) TRUE)

  expect_error(req_perform(req), class = "httr2_http_200")
})

test_that("persistent HTTP errors only get single attempt", {
  req <- request_test("/status/:status", status = 404) %>%
    req_retry(max_tries = 5)

  cnd <- req_perform(req) %>%
    expect_error(class = "httr2_http_404") %>%
    catch_cnd("httr2_fetch")
  expect_equal(cnd$n, 1)
})

test_that("repeated transient errors still fail", {
  req <- request_test("/status/:status", status = 429) %>%
    req_retry(max_tries = 3, backoff = ~ 0)

  cnd <- req_perform(req) %>%
    expect_error(class = "httr2_http_429") %>%
    catch_cnd("httr2_fetch")
  expect_equal(cnd$n, 3)
})

test_that("can cache requests with etags", {
  req <- request_test("/etag/:etag", etag = "abc") %>% req_cache(tempfile())

  resp1 <- req_perform(req)
  expect_condition(resp2 <- req_perform(req), class = "httr2_cache_not_modified")
})

test_that("can retrieve last request and response", {
  req <- request_test()
  resp <- req_perform(req)

  expect_equal(last_request(), req)
  expect_equal(last_response(), resp)
})

test_that("can last response is NULL if it fails", {
  req <- request("frooble")
  try(req_perform(req), silent = TRUE)

  expect_equal(last_request(), req)
  expect_equal(last_response(), NULL)
})

test_that("checks verbosity value", {
  req <- request_test()
  expect_snapshot(req_perform(req, verbosity = 1.5), error = TRUE)
})

# dry run -----------------------------------------------------------------

test_that("req_dry_run() returns useful data", {
  resp <- request("http://example.com") %>% req_dry_run(quiet = TRUE)
  expect_equal(resp$method, "GET")
  expect_equal(resp$path, "/")
  expect_match(resp$headers$`user-agent`, "libcurl")
})

test_that("req_dry_run() shows body", {
  # For reasons I don't understand, returns binary data in R 3.4
  skip_if_not(getRversion() >= "3.5")

  expect_snapshot({
    request("http://example.com") %>%
      req_headers(`Accept-Encoding` = "gzip") %>%
      req_body_json(list(x = 1, y = TRUE, z = "c")) %>%
      req_user_agent("test") %>%
      req_dry_run()
  })
})

test_that("authorization headers are redacted", {
  expect_snapshot({
    request("http://example.com") %>%
      req_headers(`Accept-Encoding` = "gzip") %>%
      req_auth_basic("user", "password") %>%
      req_user_agent("test") %>%
      req_dry_run()
  })
})

