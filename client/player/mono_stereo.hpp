#pragma once

#include <cstddef>
#include <cstdint>

namespace player
{

void duplicateMonoToStereo(const void* source, void* dest, std::size_t frames, std::uint16_t sample_size);

}
