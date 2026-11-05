/* VRC Pro가 쓰는 WMI 쿼리를 그대로 실행해 결과 개수와 값을 출력하는 테스트 */
#define COBJMACROS
#include <windows.h>
#include <wbemidl.h>
#include <stdio.h>

static void run(IWbemServices *svc, const wchar_t *q, const wchar_t *prop)
{
    IEnumWbemClassObject *e = NULL;
    BSTR lang = SysAllocString(L"WQL"), query = SysAllocString(q);
    HRESULT hr = IWbemServices_ExecQuery(svc, lang, query,
        WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY, NULL, &e);
    wprintf(L"\nQUERY: %ls\n  hr=0x%08lx\n", q, hr);
    if (SUCCEEDED(hr)) {
        IWbemClassObject *o; ULONG n; int count = 0;
        while (IEnumWbemClassObject_Next(e, WBEM_INFINITE, 1, &o, &n) == S_OK && n) {
            VARIANT v; VariantInit(&v);
            if (prop && SUCCEEDED(IWbemClassObject_Get(o, prop, 0, &v, NULL, NULL)) && V_VT(&v) == VT_BSTR)
                wprintf(L"  [%d] %ls = %ls\n", count, prop, V_BSTR(&v));
            VariantClear(&v);
            IWbemClassObject_Release(o);
            count++;
        }
        wprintf(L"  rows=%d\n", count);
        IEnumWbemClassObject_Release(e);
    }
    SysFreeString(lang); SysFreeString(query);
}

int main(void)
{
    IWbemLocator *loc; IWbemServices *svc; BSTR ns = SysAllocString(L"root\\cimv2");
    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    CoInitializeSecurity(NULL, -1, NULL, NULL, RPC_C_AUTHN_LEVEL_DEFAULT, RPC_C_IMP_LEVEL_IMPERSONATE, NULL, EOAC_NONE, NULL);
    if (FAILED(CoCreateInstance(&CLSID_WbemLocator, NULL, CLSCTX_INPROC_SERVER, &IID_IWbemLocator, (void **)&loc))) return 1;
    if (FAILED(IWbemLocator_ConnectServer(loc, ns, NULL, NULL, NULL, 0, NULL, NULL, &svc))) return 2;

    run(svc, L"SELECT * FROM Win32_NetworkAdapter WHERE NetConnectionID LIKE \"%\" AND MACAddress LIKE \"%\"", L"MACAddress");
    run(svc, L"SELECT * FROM Win32_NetworkAdapter WHERE NetConnectionID LIKE \"%\" AND MACAddress LIKE \"%\"", L"NetConnectionID");
    run(svc, L"SELECT * FROM Win32_DiskDrive", L"PNPDeviceID");
    run(svc, L"SELECT * FROM Win32_BaseBoard", L"SerialNumber");
    run(svc, L"ASSOCIATORS OF {Win32_LogicalDisk.DeviceID=\"C:\"} WHERE AssocClass = Win32_LogicalDiskToPartition", L"DeviceID");
    run(svc, L"ASSOCIATORS OF {Win32_DiskPartition.DeviceID=\"Disk #0, Partition #0\"} WHERE AssocClass = Win32_DiskDriveToDiskPartition", L"PNPDeviceID");
    run(svc, L"SELECT * FROM Win32_DiskDrive WHERE PnPDeviceID=\"IDE\\Disk\\VEN_WINE\"", L"SerialNumber");
    run(svc, L"SELECT * FROM Win32_DiskDrive WHERE PnPDeviceID=\"IDE\\\\Disk\\\\VEN_WINE\"", L"SerialNumber");
    run(svc, L"SELECT SameElement FROM Win32_PnPDevice", L"SameElement");
    run(svc, L"SELECT SameElement FROM Win32_PnPDevice", L"SystemElement");
    run(svc, L"SELECT * FROM Win32_SCSIControllerDevice", L"Dependent");

    IWbemServices_Release(svc); IWbemLocator_Release(loc); CoUninitialize();
    return 0;
}
