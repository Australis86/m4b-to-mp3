def pad_left($len; $chr):
    (tostring | length) as $l
    | "\($chr * ([$len - $l, 0] | max) // "")\(.)"
    ;
def pad_left($len):
    pad_left($len; "0")
    ;
