#include "uart.h"

int main(void)
{
    uart_init();

    uart_send("Hello CMake");

    return 0;
}
