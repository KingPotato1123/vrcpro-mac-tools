/* Wine 안에서 vulkan-1.dll로 Vulkan 인스턴스를 만들 수 있는지 확인 (헤더 없이 최소 구조체만 정의) */
#include <windows.h>
#include <stdio.h>
#include <string.h>

typedef struct { int sType; const void *pNext; unsigned flags; const void *pAppInfo;
                 unsigned layerCount; const char *const *layers;
                 unsigned extCount; const char *const *exts; } VkInstanceCreateInfo;
typedef struct { char name[256]; unsigned specVersion; } VkExtensionProperties;
typedef int (__stdcall *PFN_create)(const VkInstanceCreateInfo *, const void *, void **);
typedef int (__stdcall *PFN_enumext)(const char *, unsigned *, VkExtensionProperties *);
typedef int (__stdcall *PFN_enumdev)(void *, unsigned *, void **);

int main(void)
{
    HMODULE m = LoadLibraryA("vulkan-1.dll");
    printf("LoadLibrary(vulkan-1) = %p err=%lu\n", (void *)m, GetLastError());
    if (!m) return 1;
    PFN_enumext enumext = (PFN_enumext)GetProcAddress(m, "vkEnumerateInstanceExtensionProperties");
    unsigned n = 0;
    int r = enumext(NULL, &n, NULL);
    printf("instance extensions: r=%d count=%u\n", r, n);
    VkExtensionProperties props[64];
    if (n > 64) n = 64;
    enumext(NULL, &n, props);
    for (unsigned i = 0; i < n; i++) printf("  %s\n", props[i].name);

    VkInstanceCreateInfo ci = { 1 /* VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO */ };
    void *inst = NULL;
    r = ((PFN_create)GetProcAddress(m, "vkCreateInstance"))(&ci, NULL, &inst);
    printf("vkCreateInstance r=%d inst=%p\n", r, inst);
    if (r == 0) {
        unsigned d = 0;
        r = ((PFN_enumdev)GetProcAddress(m, "vkEnumeratePhysicalDevices"))(inst, &d, NULL);
        printf("physical devices: r=%d count=%u\n", r, d);
    }
    return 0;
}
