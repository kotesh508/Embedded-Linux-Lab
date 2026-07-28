#include <stdio.h>
#include "uart.h"

void uart_init(void)
{
    printf("UART Driver Initialized\n");
}

void uart_send(const char *msg)
{
    printf("UART TX : %s\n", msg);
}
