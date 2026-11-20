#include "mono_stereo.hpp"


namespace player
{

namespace
{

template <typename Sample>
void duplicateTypedMono(const void* source, void* dest, std::size_t frames)
{
    const auto* mono = static_cast<const Sample*>(source);
    auto* stereo = static_cast<Sample*>(dest);
    for (std::size_t frame = 0; frame < frames; ++frame)
    {
        stereo[frame * 2] = mono[frame];
        stereo[frame * 2 + 1] = mono[frame];
    }
}

} // namespace


void duplicateMonoToStereo(const void* source, void* dest, std::size_t frames, std::uint16_t sample_size)
{
    if ((source == nullptr) || (dest == nullptr))
        return;

    if (sample_size == sizeof(std::int16_t))
        duplicateTypedMono<std::int16_t>(source, dest, frames);
    else if (sample_size == sizeof(std::int32_t))
        duplicateTypedMono<std::int32_t>(source, dest, frames);
}

} // namespace player
