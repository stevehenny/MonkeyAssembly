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
    .eqv LAST_COLUMN 76                 # 79 - last two columns don't show on screen
    .eqv LAST_ROW 29                    # 31 - last two rows don't show on screen
    .eqv ADDRESSES_PER_ROW 512
    .eqv NEG_ADDRESSES_PER_ROW -512
    .eqv STARTING_LOC 0x8204            # The VGA memory address wher ethe 'starting' character is located.
                                        # 1,2 or 0x8000+1*4+2*512=0x8204
    .eqv ENDING_LOC 0xb700              # The VGA memory address where the 'ending character' is located
                                        # 64, 27 or 0x8000+64*4+27*512=0xb700
    .eqv BLOCK_LOC 0x987C               # The VGA memory address where the 'block character' is located
                                        # 31, 12 or 0x8000+31*4+12*512=0x987C
    .eqv SEGMENT_TIMER_INTERVAL 100     # This constant represents the number of timer ticks (each 1 ms)
                                        # that are needed before incrementing the timer value on the seven
                                        # segment display. With a value of 100, the timer will increment
                                        # every 100 ms (or 10 times a second).

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

    # Call main program procedure
    jal MOVE_CHAR_GAME

    # End in infinite loop (should never get here)
END_MAIN:
    j END_MAIN

MOVE_CHAR_GAME:
    