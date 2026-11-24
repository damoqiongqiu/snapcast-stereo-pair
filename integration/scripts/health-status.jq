[
  .result.server.streams[]
  | select(.id == "LeftAudio" or .id == "RightAudio")
  | {
      id: .id,
      format: .uri.query.sampleformat,
      status: .status
    }
] as $streams
| if ($streams | length) != 2 then
    "stream set is incomplete" | halt_error(1)
  elif any($streams[]; .format != "48000:24:1") then
    "stream format is not 48000:24:1" | halt_error(1)
  elif any($streams[]; .status != "playing") then
    "stream is idle: \([$streams[] | select(.status != "playing") | .id] | join(", "))" | halt_error(1)
  else
    empty
  end
