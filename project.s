#######################
#
# Filename: project.s
#
# Author: Stephen Henstrom
# Class: ECEn 323, Section 002, Winter 2024
# Date: 4/3/2024
#
# This is an implementation of Snake in assembly on the Artix-7 FPGA board
#
# Memory Organization:
#   0x0000-0x1fff : text
#   0x2000-0x3fff : data
# Registers:
#   x0: Zero
#   x1: return address
#   x2 (sp): stack pointer (starts at 0x3ffc)
#   x3 (gp): global pointer (to data: 0x2000)
#   x10-x11: function arguments/return values
#
# Functions:
#	- main
#######################

.globl  main

.text


# I/O address offset constants
    .eqv LED_OFFSET 0x0
    .eqv SWITCH_OFFSET 0x4
    .eqv SEVENSEG_OFFSET 0x18
    .eqv BUTTON_OFFSET 0x24
    .eqv CHAR_COLOR_OFFSET 0x34
    .eqv TIMER 0x30

# I/O mask constants
    .eqv BUTTON_C_MASK 0x01
    .eqv BUTTON_L_MASK 0x02
    .eqv BUTTON_D_MASK 0x04
    .eqv BUTTON_R_MASK 0x08
    .eqv BUTTON_U_MASK 0x10

# Game specific constants
    .eqv CHAR_A 0x41                    # ASCII 'A'
    .eqv CHAR_A_RED 0x0fff00C1          # 'A' character with red foreground, black background
    .eqv CHAR_C 0x43                    # ASCII 'C'
    .eqv CHAR_C_YELLOW 0x00fff0C3       # 'C' character with yellow foreground, black background
    .eqv CHAR_Z 0x5A                    # ASCII 'Z'
    .eqv CHAR_Z_MAGENTA 0x0f0f0fDA      # 'Z' character with magenta foreground, black background
    .eqv CHAR_SPACE 0x20                # ASCII ' '
    .eqv COLUMN_MASK 0x1fc              # Mask for the bits in the VGA address for the column
    .eqv COLUMN_SHIFT 2                 # Number of right shifts to determine VGA column
    .eqv ROW_MASK 0x3e00                # Mask for the bits in the VGA address for the row
    .eqv ROW_SHIFT 9                    # Number of right shifts to determine VGA row
    .eqv FIRST_COLUMN 3                 # 3 - snake can't go past this column
    .eqv FIRST_ROW 4                    # 4 - snake can't go past this row
    .eqv LAST_COLUMN 76                 # 76 - snake can't go past this column
    .eqv LAST_ROW 25                    # 25 - snake can't go past this row
    .eqv INIT_ROW_LOC 14
    .eqv INIT_COL_LOC 38
    .eqv ARRAY_OFFSET 0x4               # Offset for the array of snake locations
    .eqv ADDRESSES_PER_ROW 512
    .eqv NEG_ADDRESSES_PER_ROW -512
    .eqv STARTING_LOC 0x8204            # The VGA memory address wher ethe 'starting' character is located.
                                        # 1,2 or 0x8000+1*4+2*512=0x8204
    .eqv ENDING_LOC 0xb700              # The VGA memory address where the 'ending character' is located
                                        # 64, 27 or 0x8000+64*4+27*512=0xb700
    .eqv BLOCK_LOC 0x987C               # The VGA memory address where the 'block character' is located
                                        # 31, 12 or 0x8000+31*4+12*512=0x987C
    .eqv SEGMENT_TIMER_INTERVAL 250     # This constant represents the number of timer ticks (each 1 ms)
                                        # that are needed before incrementing the timer value on the seven
                                        # segment display. With a value of 100, the timer will increment
                                        # every 250 ms (or 4 times a second).

    .eqv INIT_FASTEST_SCORE 0xffff      # Fastest score initialized to 0xffff (should get lower with better play)

main:
     # The purpose of this initial section is to setup the global registers that
    # will be used for the entire program execution. This setup portion will only
    # be run once.

    # Setup the stack pointer: sp = 0x3ffc
    li sp, 0x3ffc
    # The previous "pseudo instruction" will be compiled into the following two instructions:
    #  lui sp, 4		# 4 << 12 = 0x4000
    #  addi sp, sp, -4		# 0x4000 - 4 = 0x3ffc

    # setup the global pointer to the data segment (2<<12 = 0x2000)
    lui gp, 2

    # Prepare I/O base address
    li tp, 0x7f00
 
    # Prepare VGA base address
    li s0, 0x8000
    
    #initialize pointer to array of snake locations in data memory
    add s1, gp, x0
    
    #initialize counter of how many items are in array s1
    addi s2, x0, 0

    
GENERATE_APPLE:

    #clear all temporary registers
    xor t0, t0, t0
    xor t1, t1, t1
    xor t2, t2, t2
    xor t3, t3, t3
    xor t4, t4, t4
    xor t5, t5, t5
    xor t6, t6, t6

    # Generate random row and column for apple location
    li t3, 0x8000  # Starting address of VGA memory

    # Load the address of GENERATE_RANDOM_ROW into a register
    lui t0, %hi(GENERATE_RANDOM_ROW)
    addi t0, t0, %lo(GENERATE_RANDOM_ROW)

    # Jump to GENERATE_RANDOM_ROW using jalr
    jalr ra, t0, 0              # ra is the return address
    add t1, x0, a0              # Store random row in t1
    slli t1, t1, ROW_SHIFT      # Shift row to correct location in VGA memory
    add t3, t3, t1              # Add row to VGA memory address

    # Generate random column
    xor t0, t0, t0              # Clear t0
    lui t0, %hi(GENERATE_RANDOM_COLUMN) # Load the address of GENERATE_RANDOM_COLUMN into a register
    addi t0, t0, %lo(GENERATE_RANDOM_COLUMN) # Add the offset of GENERATE_RANDOM_COLUMN to the address

    jalr ra, t0, 0              # ra is the return address
    add t1, x0, a0              # Store random column in t1
    slli t1, t1, COLUMN_SHIFT   # Shift column to correct location in VGA memory
    add t3, t3, t1              # Add column to VGA memory address

    # Store apple VGA Location in s3
    add s3, x0, t3

INITIALIZE_SNAKE:
    #initialize the first location of the snake head
    #This puts the offsets for the row and the column for the initial vga location
    #into t1 and t0 respectively
    addi t0, x0, INIT_COL_LOC
    addi t1, x0, INIT_ROW_LOC
    slli t0, t0, COLUMN_SHIFT
    slli t1, t1, ROW_SHIFT
    
    # put the inital VGA location of snake head into t2 
    add t2, s0, x0
    add t2, t2, t1
    add t2, t2, t0
    
    # Now store the word in the offset of our
    add t3, x0, x0          # t3 is the offset of the array location where the snake head will be stored
    addi t3, t3, ARRAY_OFFSET# t3 now holds the offset of the array location where the snake head will be stored
    mul t4, s2, t3          # t4 now holds the offset of the array location where the snake head will be stored
    add s1, s1, t4          # s1 now points to the location in the array where the snake head is stored
    sw t2, 0(s1)            # store the VGA location of the snake head in the array
    addi s2, s2, 1          # increment the number of items in the array

    # Call main program procedure
    jal MOVE_CHAR_GAME

    # End in infinite loop (should never get here)
END_MAIN:
    j END_MAIN

GENERATE_RANDOM_ROW:
    # Generate a random number between 5 and 32
    li a1, FIRST_ROW    # Lower bound (inclusive)
    li a2, LAST_ROW   # Upper bound (inclusive)
    li a7, 0x12 # Random number generation code with bounds
    ecall
    ret

GENERATE_RANDOM_COLUMN:
    # Generate a random number between 3 and 76
    li a1, FIRST_COLUMN    # Lower bound (inclusive)
    li a2, LAST_COLUMN   # Upper bound (inclusive)
    li a7, 0x12 # Random number generation code with bounds
    ecall
    ret

MOVE_CHAR_GAME:
    