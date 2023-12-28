.global _start

.section .data
    number:    .byte 5
    result:    .word 1

.section .text
_start:
    ldr r3, =1          // Initialize loop counter
    ldr r2, =1          // Initialize result to 1

calculate_factorial:
    cmp r3, #0           // Compare counter with 0
    ble end_calculation  // If counter <= 0, jump to the end

    mul r2, r2, r3       // Multiply result by counter
    sub r3, r3, #1       // Decrement counter
    b calculate_factorial // Branch back to the beginning of the loop

end_calculation:
    // The result is now stored in the r2 register

    // Add your code here to do something with the result
    // For example, you can print it to the console

    // Exit the program
    mov r7, #1           // syscall: exit
    mov r0, #0           // status: 0
    swi 0x0              // Call kernel
