/* Wine이 알려 주는 현재 화면 모드와 지원 모드 목록 출력 */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    DEVMODEA dm = { .dmSize = sizeof(dm) };
    DWORD i;
    if (EnumDisplaySettingsA(NULL, ENUM_CURRENT_SETTINGS, &dm))
        printf("current: %lux%lu @%luHz %lubpp\n", dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency, dm.dmBitsPerPel);
    for (i = 0; EnumDisplaySettingsA(NULL, i, &dm); i++)
        if (dm.dmBitsPerPel == 32) printf("mode: %lux%lu @%luHz\n", dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency);
    return 0;
}
