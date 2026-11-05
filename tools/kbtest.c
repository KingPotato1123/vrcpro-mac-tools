/* Wine의 현재 키보드 배열과 ActivateKeyboardLayout 동작을 확인하는 테스트 */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    HKL list[16];
    int i, n = GetKeyboardLayoutList(16, list);
    HKL cur = GetKeyboardLayout(0), us, r;

    printf("current layout = %08lx, user locale = %04x\n", (unsigned long)(ULONG_PTR)cur, GetUserDefaultLCID());
    for (i = 0; i < n; i++) printf("  list[%d] = %08lx\n", i, (unsigned long)(ULONG_PTR)list[i]);

    us = LoadKeyboardLayoutA("00000409", KLF_ACTIVATE);
    printf("LoadKeyboardLayout(00000409) = %08lx, err=%lu\n", (unsigned long)(ULONG_PTR)us, GetLastError());
    SetLastError(0);
    r = ActivateKeyboardLayout((HKL)(ULONG_PTR)0x04090409, 0);
    printf("ActivateKeyboardLayout(04090409) = %08lx, err=%lu\n", (unsigned long)(ULONG_PTR)r, GetLastError());
    printf("current layout after = %08lx\n", (unsigned long)(ULONG_PTR)GetKeyboardLayout(0));
    return 0;
}
