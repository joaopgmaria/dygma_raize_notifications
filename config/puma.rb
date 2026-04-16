# Single thread — all requests are serialised through the keyboard mutex anyway,
# and fewer threads means less GIL contention with animation threads.
threads 1, 1
workers 0
