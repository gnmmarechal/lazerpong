INCLUDE "macros.asm"
INCLUDE "constants.asm"
INCLUDE "charmap.asm"

SECTION "rst 00", ROM0 [$00]
    ret

SECTION "rst 08", ROM0 [$08]
    ret

SECTION "rst 10", ROM0 [$10]
    ret

SECTION "rst 18", ROM0 [$18]
    jp JumpToFuncInTable

SECTION "rst 20", ROM0 [$20]
    ret

SECTION "rst 28", ROM0 [$28]
    ret

SECTION "rst 30", ROM0 [$30]
    ret

SECTION "rst 38", ROM0 [$38]
    ret

SECTION "VBlank", ROM0 [$40]
    jp VBlankInterruptHandler

SECTION "LCDC",ROM0[$48]
    reti

SECTION "Timer", ROM0 [$50]
    jp TimerInterruptHandler

SECTION "Serial",ROM0[$58]
    jp SerialInterruptHandler

SECTION "Joypad", ROM0 [$60]
    reti


SECTION "Entry", ROM0 [$100]

Entry: ; 0x100
	nop
	jp Start

SECTION "Header", ROM0 [$104]
	; The header is generated by rgbfix.
	; The space here is allocated to prevent code from being overwritten.
	ds $150 - $104

SECTION "Main", ROM0 [$150]

Start: ; 0x150
    di
    ld sp, $ffff
    xor a
    ld [rLCDC], a  ; Disable LCD Display
    ld hl, $c000
    ld bc, $2000
    call ClearData  ; Clear working RAM
    ld hl, vTiles0
    ld bc, $2000
    call ClearData  ; Clear VRAM
    ld hl, $fe00
    ld bc, $a0
    call ClearData  ; Clear OAM
    ld hl, $ff80
    ld bc, $7d  ; Clear HRAM
    call ClearData
    ld hl, GameGfx
    ld bc, $800
    ld de, vTiles0
    call LoadGfx
    ld a, %11100100
    ld [rBGP], a  ; Set Background palette
    ld [rOBP0], a ; Set Sprite Palette 0
    ld [rOBP1], a ; Set Sprite Palette 1

    call ClearOAMBuffer
    call ClearBackground

    ld sp, $dfff  ; Initialize stack pointer to end of working RAM

    call WriteDMACodeToHRAM

    xor a
    ld hl, wCurrentScreen
    ld [hli], a
    ld [hl], a

    ld a, $93
    ld [rLCDC], a   ; Enable LCD Display
    ld a,%00000001  ; Enable V-blank interrupt
    ld [rIE], a
    ei
    jp Main

JumpToFuncInTable:
; Jumps to a function in the pointer table immediately following
; a "rst $18" call.  Function must be in the same Bank as the pointer table.
    sla a
    pop hl
    push de
    ld e, a
    ld d, $0
    add hl, de
    ld e, [hl]
    inc hl
    ld d, [hl]
    ld l, e
    ld h, d
    pop de
    jp [hl]

VBlankInterruptHandler:
    push af
    push bc
    push de
    push hl
    call ReadJoypad
    call DrawCurrentScreen
    ld a, 1
    ld [VBlankFlag], a
    pop hl
    pop de
    pop bc
    pop af
    reti

DrawCurrentScreen:
    ld a, [wCurrentScreen]
    rst $18
DrawScreenFunctions:
    dw DrawTitlescreen
    dw DrawGame

DrawTitlescreen:
    jp $ff80  ; OAM DMA transfer

DrawGame:
    call DrawScore
    call DrawPlayerPaddle
    call DrawComputerPaddle
    ; Draw OAM sprites
    call ClearOAMBuffer
    call DrawBall
    call DrawLasers
    jp $ff80  ; OAM DMA transfer

TimerInterruptHandler:
    reti

SerialInterruptHandler:
    reti

; copies DMA routine to HRAM. By GB specifications, all DMA needs to be done in HRAM (no other memory section is available during DMA)
; This routine is taken from Pokemon Red Version.
WriteDMACodeToHRAM: ; 4bed (1:4bed)
    ld c, $80
    ld b, $a
    ld hl, DMARoutine
.copyLoop
    ld a, [hli]
    ld [$ff00+c], a
    inc c
    dec b
    jr nz, .copyLoop
    ret

DMARoutine: ; 4bfb (1:4bfb)
    ld a, (wOAMBuffer >> 8)
    ld [$ff00+$46], a   ; start DMA
    ld a, $28
.waitLoop               ; wait for DMA to finish
    dec a
    jr nz, .waitLoop
    ret

ClearData:
; Clears bc bytes starting at hl with value in a.
; bc can be a maximum of $7fff, since it checks bit 7 of b when looping.
    dec bc
.clearLoop
    ld [hli], a
    dec bc
    bit 7, b
    jr z, .clearLoop
    ret

CopyData:
; Copies bc bytes starting at hl to de.
    ld a, [hli]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c  ; have we copied all of the data?
    jr nz, CopyData
    ret

ClearOAMBuffer:
; Fills OAM buffer memory with $0.
    xor a
    ld hl, wOAMBuffer
    ld bc, $a0  ; size of OAM buffer
    jp ClearData

ClearBackground:
; Fills Background memory with $1.
    ld a, 1
    ld hl, vBGMap0
    ld bc,$800  ; size of background memory
    jp ClearData

ClearLasers:
; Deletes all lasers
    xor a
    ld hl, wLasers
    ld bc, (MAX_LASERS * 2 * 5)
    jp ClearData

LoadGfx:
; This loads data into VRAM. It waits for the LCD H-Blank to copy the data.
; input:  hl = source of data
;         de = destination for data
;         bc = number of bytes to copy
.waitForHBlank
    ld a, [$ff41] ; LCDC Status
    and $3
    jr nz, .waitForHBlank
    ld a, [hli]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c  ; have we copied all of the data?
    jr nz, .waitForHBlank
    ret

ClearGfx:
; Clear data in VRAM. It waits for the LCD H-Blank to clear the data.
; input:  hl = destination to clear
;         bc = number of bytes to clear
;          d = value to clear with
.waitForHBlank
    ld a, [$ff41] ; LCDC Status
    and $3
    jr nz, .waitForHBlank
    ld a, d
    ld [hli], a
    dec bc
    ld a, b
    or c  ; have we cleared all of the data?
    jr nz, .waitForHBlank
    ret

PrintText:
; Loads text graphics.
; input:  hl = pointer to "@"-terminated string
;         de = destination for data
    ld bc, $0000  ; Count number of bytes in string
    push hl
.loop
    ld a, [hli]
    cp "@"
    jr z, .finishedProcessingString
    inc bc
    jr .loop
.finishedProcessingString
    pop hl
    jp LoadGfx

ReadJoypad:
; Reads the current state of the joypad and saves the state into
; some registers the game uses during gameplay.
    ld a, $20
    ld [rJOYP], a
    ld a, [rJOYP]
    ld a, [rJOYP]
    and $f
    swap a
    ld b, a
    ld a, $30
    ld [rJOYP], a
    ld a, $10
    ld [rJOYP], a
    ld a, [rJOYP]
    ld a, [rJOYP]
    ld a, [rJOYP]
    ld a, [rJOYP]
    ld a, [rJOYP]
    ld a, [rJOYP]
    and $f
    or b
    cpl  ; a contains currently-pressed buttons
    ld [hJoypadState], a
    ret

ResetScores:
    xor a
    ld hl, wPlayerScore
    ld [hli], a
    ld [hl], a
    ret

InitPlayerPaddle:
; Initializes the player's paddle.
    ld hl, wPlayerY
    ld a, $00
    ld [hli], a
    ld a, $17
    ld [hl], a
    ld a, $18
    ld [wPlayerHeight], a
    ret

InitPlayerLasers:
; Initializes the player's lasers.
    xor a
    ld hl, wPlayerLasers
    ld bc, 5 * MAX_LASERS
    jp ClearData

InitComputerPaddle:
; Initializes the computer's paddle.
    ld hl, wComputerY
    ld a, $00
    ld [hli], a
    ld a, $17
    ld [hl], a
    ld a, $18
    ld [wComputerHeight], a
    ret

InitComputerLasers:
; Initializes the Computer's lasers.
    xor a
    ld hl, wComputerLasers
    ld bc, 5 * MAX_LASERS
    jp ClearData

DrawScore:
; Draws the score of the game.
    ld a, [wPlayerScore]
    cp 10
    jr c, .oneDigit
    push af
    ld a, $21
    hlCoord 2, 3, vBGMap0
    ld [hl], a
    pop af
    sub 10
.oneDigit
    add $20  ; base tile id for numbers
    hlCoord 3, 3, vBGMap0
    ld [hl], a
    ld a, [wComputerScore]
    cp 10
    jr c, .oneDigit2
    push af
    ld a, $21
    hlCoord 16, 3, vBGMap0
    ld [hl], a
    pop af
    sub 10
.oneDigit2
    add $20  ; base tile id for numbers
    hlCoord 17, 3, vBGMap0
    ld [hl], a
    ret

DrawPlayerPaddle:
; Draws the player's paddle to the screen.
; This also fills in blank tiles along the column where the player's paddle doesn't overlap.
    ld a, [wPlayerY + 1]
    push af
    srl a
    srl a
    srl a  ; Divide by 8 to get the tile index we need to start drawing at.
    hlCoord 0, 0, vBGMap0
    ld bc, $0020
    ld d, $00  ; Count which tile row we're on.
.addLoop
    ld [hl], $01
    and a
    jr z, .gotHLCoord
    inc d
    add hl, bc  ; Move the HL Coord down one row of tiles.
    dec a
    jr .addLoop
.gotHLCoord
    pop af  ; Reload player's paddle Y position
    and $7  ; Get the pixel offset in the tile. (Tiles are 8 pixels wide)
    jr z, .save8
    push af
    ld e, a
    ld a, 8
    sub e
    ld e, a
    pop af
    jr .drawTile
.save8
    ld e, 8
.drawTile
    add $10  ; a now contains tile id for the top tile
    ld [hl], a  ; Draw the top tile
    inc d
    ld a, [wPlayerHeight]
    sub e
.drawMiddleTiles
    add hl, bc
    cp a, 8
    jr c, .drawBottomTile
    sub 8
    ld [hl], $10  ; Tile id of the solid paddle tile.
    inc d
    jr .drawMiddleTiles
.drawBottomTile
    and a
    jr z, .clearRemainingTiles
    add $18
    ld [hl], a
    inc d
    ld a, d
.clearRemainingTiles
    cp 18 ; number of rows in the display
    jr z, .done
    add hl, bc
    ld [hl], $01  ; blank tile
    inc a
    jr .clearRemainingTiles
.done
    ret

DrawLasers:
; Loads the player's and the computer's laser sprites into the OAM buffer.
    ld hl, wLasers
    ld de, wLaserSprites    ; OAM buffer destination for laser sprites
    ld b, 1 + (MAX_LASERS * 2)  ; We're drawing both the player's and the computer's lasers
.loop
    dec b
    ret z
    ld a, [hli]  ; check if laser is active
    and a
    jr nz, .activeLaser
    ; Laser is inactive, so don't draw it
    push bc
    ld bc, $0004
    add hl, bc  ; Move to next laser struct
    pop bc
    jr .loop
.activeLaser
    inc hl  ; Skip over the low byte of the y position
    ld a, [hli]  ; y position (high byte)
    add 16 - 4  ; adjust for sprite screen offset (and center the sprite)
    ld [de], a
    inc de
    inc hl  ; Skip over the low byte of the x position
    ld a, [hli]  ; x position (high byte)
    add 8 - 4  ; adjust for sprite screen offset (and center the sprite)
    ld [de], a
    inc de
    ld a, $2  ; Laser tile id
    ld [de], a
    inc de
    ld a, %00000000  ; sprite attributes
    ld [de], a
    inc de
    jr .loop

DrawComputerPaddle:
; Draws the computer's paddle to the screen.
; This also fills in blank tiles along the column where the computer's paddle doesn't overlap.
    ld a, [wComputerY + 1]
    push af
    srl a
    srl a
    srl a  ; Divide by 8 to get the tile index we need to start drawing at.
    hlCoord 019, 0, vBGMap0
    ld bc, $0020
    ld d, $00  ; Count which tile row we're on.
.addLoop
    ld [hl], $01
    and a
    jr z, .gotHLCoord
    inc d
    add hl, bc  ; Move the HL Coord down one row of tiles.
    dec a
    jr .addLoop
.gotHLCoord
    pop af  ; Reload computer's paddle Y position
    and $7  ; Get the pixel offset in the tile. (Tiles are 8 pixels wide)
    jr z, .save8
    push af
    ld e, a
    ld a, 8
    sub e
    ld e, a
    pop af
    jr .drawTile
.save8
    ld e, 8
.drawTile
    add $10  ; a now contains tile id for the top tile
    ld [hl], a  ; Draw the top tile
    inc d
    ld a, [wComputerHeight]
    sub e
.drawMiddleTiles
    add hl, bc
    cp a, 8
    jr c, .drawBottomTile
    sub 8
    ld [hl], $10  ; Tile id of the solid paddle tile.
    inc d
    jr .drawMiddleTiles
.drawBottomTile
    and a
    jr z, .clearRemainingTiles
    add $18
    ld [hl], a
    inc d
    ld a, d
.clearRemainingTiles
    cp 18 ; number of rows in the display
    jr z, .done
    add hl, bc
    ld [hl], $01  ; blank tile
    inc a
    jr .clearRemainingTiles
.done
    ret

InitBall:
; Initializes the Pong ball
    ld hl, wBallY
    xor a
    ld [hli], a
    ld a, BASE_BALL_Y_POSITION
    ld [hli], a
    xor a
    ld [hli], a
    ld a, BASE_BALL_X_POSITION
    ld [hli], a
    ld a, (BASE_BALL_Y_SPEED & $ff)
    ld [hli], a
    ld a, (BASE_BALL_Y_SPEED >> 8)
    ld [hli], a
    ld a, (BASE_BALL_X_SPEED & $ff)
    ld [hli], a
    ld a, (BASE_BALL_X_SPEED >> 8)
    ld [hl], a
    ret

PlayerScorePoint:
    ld a, [wPlayerScore]
    inc a
    ld [wPlayerScore], a
    ld a, START_PLAY_TIME
    ld [wStartPlayTimer], a
    call InitPlayerPaddle
    call InitComputerPaddle
    call InitBall
    ld hl, wBallY
    xor a
    ld [hli], a
    ld a, BASE_BALL_Y_POSITION
    ld [hli], a
    xor a
    ld [hli], a
    ld a, BASE_BALL_X_POSITION
    ld [hli], a
    ld a, (BASE_BALL_Y_SPEED & $ff)
    ld [hli], a
    ld a, (BASE_BALL_Y_SPEED >> 8)
    ld [hli], a
    ld a, (BASE_BALL_X_SPEED_NEGATIVE & $ff)
    ld [hli], a
    ld a, (BASE_BALL_X_SPEED_NEGATIVE >> 8)
    ld [hl], a
    call ClearLasers
    call CheckForGameFinished
    ret

ComputerScorePoint:
    ld a, [wComputerScore]
    inc a
    ld [wComputerScore], a
    ld a, START_PLAY_TIME
    ld [wStartPlayTimer], a
    call InitPlayerPaddle
    call InitComputerPaddle
    call InitBall
    ld hl, wBallY
    xor a
    ld [hli], a
    ld a, BASE_BALL_Y_POSITION
    ld [hli], a
    xor a
    ld [hli], a
    ld a, BASE_BALL_X_POSITION
    ld [hli], a
    ld a, (BASE_BALL_Y_SPEED & $ff)
    ld [hli], a
    ld a, (BASE_BALL_Y_SPEED >> 8)
    ld [hli], a
    ld a, (BASE_BALL_X_SPEED & $ff)
    ld [hli], a
    ld a, (BASE_BALL_X_SPEED >> 8)
    ld [hl], a
    call ClearLasers
    call CheckForGameFinished
    ret

CheckForGameFinished:
    ld a, [wComputerScore]
    cp POINTS_TO_WIN
    jr c, .checkPlayer
    ; Computer won the game
    ; TODO: do stuff when game is won
    xor a
    ld [wScreenState], a
    ld a, SCREEN_TITLESCREEN
    ld [wCurrentScreen], a
    ret
.checkPlayer
    ld a, [wPlayerScore]
    cp POINTS_TO_WIN
    ret c
    ; Player won the game
    xor a
    ld [wScreenState], a
    ld a, SCREEN_TITLESCREEN
    ld [wCurrentScreen], a
    ret

DrawBall:
; Draws the Pong ball sprite to OAM.
    ld hl, wBallSprite
    ld a, [wBallY + 1]
    add 16 - 4  ; Add 16 to adjust for the screen offset for sprites.
    ld [hli], a
    ld a, [wBallX + 1]
    add 8 - 4  ; Add 8 to adjust for the screen offset for sprites.
    ld [hli], a
    ld a, $0  ; tile id for ball's sprite
    ld [hli], a
    ld a, %00000000
    ld [hl], a
    ret

MoveBall:
; Updates the ball's position according to its speed.
    call UpdateBallYPosition
    call UpdateBallXPosition
    ret

UpdateBallYPosition:
    ld a, [wBallY]
    ld l, a
    ld a, [wBallY + 1]
    ld h, a  ; hl contains ball's y position
    ld a, [wBallYSpeed]
    ld c, a
    ld a, [wBallYSpeed + 1]
    ld b, a  ; bc contains ball's y speed
    cp $80
    jr c, .movingDown
    ; Ball is moving up because y speed is negative
    add hl, bc
    ; Check if new position is beyond the top of the screen
    ld a, h
    cp 220  ; Arbitrary large number so we can detect underflow
    jr c, .saveYPosition
    ; Invert the y speed, and set the y position equal to the top of the screen
    call InvertBC
    ; bc now contains inverted y speed
    ld a, c
    ld [wBallYSpeed], a
    ld a, b
    ld [wBallYSpeed + 1], a
    ld hl, $0000
    jr .saveYPosition
.movingDown
    ; Ball is moving down because y speed is positive
    add hl, bc
    ; Check if new position is beyond the bottom of the screen
    ld a, h
    cp 144
    jr c, .saveYPosition
    ; Invert the y speed, and set the y position equal to the bottom of the screen 
    call InvertBC
    ; bc now contains inverted y speed
    ld a, c
    ld [wBallYSpeed], a
    ld a, b
    ld [wBallYSpeed + 1], a
    ld h, 144
    ld l, 0
.saveYPosition
    ld a, l
    ld [wBallY], a
    ld a, h
    ld [wBallY + 1], a
    ret

UpdateBallXPosition:
    ld a, [wBallX]
    ld l, a
    ld a, [wBallX + 1]
    ld h, a  ; hl contains ball's x position
    ld a, [wBallXSpeed]
    ld c, a
    ld a, [wBallXSpeed + 1]
    ld b, a  ; bc contains ball's x speed
    cp $80
    jr c, .movingRight
    ; Ball is moving left because x speed is negative
    add hl, bc
    ; Check if it hit the player's wall
    ld a, h
    cp 220 ; Arbitrary large number to check for underflow
    jr c, .notTouchingLeftWall
    ; Computer scored a point!
    call ComputerScorePoint
    ret
.notTouchingLeftWall
    ; Check if the ball is hitting the player's paddle
    ld a, h
    sub 4
    cp 4
    jr c, .saveXPosition
    cp 8
    jr nc, .saveXPosition
    ld a, [wBallY + 1]
    ld e, a
    ld a, [wPlayerY + 1]
    cp e
    jr nc, .saveXPosition
    ld d, a
    ld a, [wPlayerHeight]
    add d
    cp e
    jr c, .saveXPosition
    ; Ball is hitting player's paddle
    ; Invert the x speed, and set the x position equal to the right side of player's paddle
    call InvertBC
    ; bc now contains inverted x speed
    ld a, c
    ld [wBallXSpeed], a
    ld a, b
    ld [wBallXSpeed + 1], a
    ld hl, $0c00
    jr .saveXPosition
.movingRight
    add hl, bc
    ; Check if it hit the computer's wall
    ld a, h
    cp 160 ; Pixel position of right-side wall
    jr c, .notTouchingRightWall
    ; Player scored a point!
    call PlayerScorePoint
    ret
.notTouchingRightWall
    ; Check if the ball is hitting the computer's paddle
    ld a, h
    add 4
    cp 152
    jr c, .saveXPosition
    cp 156
    jr nc, .saveXPosition
    ld a, [wBallY + 1]
    ld e, a
    ld a, [wComputerY + 1]
    cp e
    jr nc, .saveXPosition
    ld d, a
    ld a, [wComputerHeight]
    add d
    cp e
    jr c, .saveXPosition
    ; Ball is hitting computer's paddle
    ; Invert the x speed, and set the x position equal to the left side of computer's paddle
    call InvertBC
    ; bc now contains inverted x speed
    ld a, c
    ld [wBallXSpeed], a
    ld a, b
    ld [wBallXSpeed + 1], a
    ld hl, $9400
.saveXPosition
    ld a, l
    ld [wBallX], a
    ld a, h
    ld [wBallX + 1], a
    ret

InvertBC:
; Inverts the 16-bit value in bc
    ld a, b
    cpl
    ld b, a
    ld a, c
    cpl
    ld c, a
    inc c
    ret nz
    inc b
    ret

MoveLasers:
; Updates laser positions according to their speeds.
    call MovePlayerLasers
    jp MoveComputerLasers

MovePlayerLasers:
    ld hl, wPlayerLasers
    ld b, MAX_LASERS + 1
.loop
    dec b
    ret z
    ld a, [hli]
    and a
    jr nz, .activeLaser
    inc hl
    inc hl
    inc hl
    inc hl  ; Move to next laser struct
    jr .loop
.activeLaser
    inc hl
    inc hl
    push hl  ; Save pointer to y position
    ld a, [hli]
    ld e, a
    ld a, [hl]
    ld d, a  ; de contains laser x position
    ld hl, BASE_LASER_SPEED_RIGHT
    add hl, de
    ld d, h
    ld e, l
    pop hl
    ld a, e
    ld [hli], a
    ld a, d
    ld [hli], a
    jr .loop

MoveComputerLasers:
    ld hl, wComputerLasers
    ld b, MAX_LASERS + 1
.loop
    dec b
    ret z
    ld a, [hli]
    and a
    jr nz, .activeLaser
    inc hl
    inc hl
    inc hl
    inc hl  ; Move to next laser struct
    jr .loop
.activeLaser
    inc hl
    inc hl
    push hl  ; Save pointer to y position
    ld a, [hli]
    ld e, a
    ld a, [hl]
    ld d, a  ; de contains laser x position
    ld hl, BASE_LASER_SPEED_LEFT
    add hl, de
    ld d, h
    ld e, l
    pop hl
    ld a, e
    ld [hli], a
    ld a, d
    ld [hli], a
    jr .loop

ShootLasers:
    call ShootPlayerLasers
    call ShootComputerLasers
    ret

ShootPlayerLasers:
; If player is pressing "shoot" button, fire a laser.
    ld a, [hJoypadState]
    bit BIT_A_BUTTON, a
    jr z, .done
    ld a, [wPlayerLaserCooldown]
    and a
    jr nz, .done
    ld hl, wPlayerLasers
    ld b, MAX_LASERS + 1
    ; Loop to find the first inactive laser, if there is one
.loop
    dec b
    jr z, .done  ; Maximum number of lasers are currently in play
    ld a, [hl]
    and a
    jr z, .foundInactiveLaser
    ; Check the next laser
    inc hl
    inc hl
    inc hl
    inc hl
    inc hl
    jr .loop
.foundInactiveLaser
    ld a, 1
    ld [hli], a  ; Set laser state to "active"
    ; Set laser's position in front of the player's paddle
    xor a
    ld [hli], a  ; Set low byte of laser's y position
    ld a, [wPlayerY + 1]
    ld c, a
    ld a, [wPlayerHeight]
    srl a
    add c  ; a is now the y-midpoint of the player's paddle
    ld [hli], a
    xor a
    ld [hli], a
    ld a, $a
    ld [hli], a  ; Set the laser's x position just to the right of the player's paddle
    ; Player has to wait awhile before firing another laser
    ld a, LASER_COOLDOWN
    ld [wPlayerLaserCooldown], a
    ret
.done
    ; Decrement the cooldown counter
    ld a, [wPlayerLaserCooldown]
    and a
    ret z
    dec a
    ld [wPlayerLaserCooldown], a
    ret

ShootComputerLasers:
; TODO: Do some logic to determine if computer should shoot a laser
    ld a, [wComputerLaserCooldown]
    and a
    jr nz, .done
    ld hl, wComputerLasers
    ld b, MAX_LASERS + 1
    ; Loop to find the first inactive laser, if there is one
.loop
    dec b
    jr z, .done  ; Maximum number of lasers are currently in play
    ld a, [hl]
    and a
    jr z, .foundInactiveLaser
    ; Check the next laser
    inc hl
    inc hl
    inc hl
    inc hl
    inc hl
    jr .loop
.foundInactiveLaser
    ld a, 1
    ld [hli], a  ; Set laser state to "active"
    ; Set laser's position in front of the computer's paddle
    xor a
    ld [hli], a  ; Set low byte of laser's y position
    ld a, [wComputerY + 1]
    ld c, a
    ld a, [wComputerHeight]
    srl a
    add c  ; a is now the y-midpoint of the computer's paddle
    ld [hli], a
    xor a
    ld [hli], a
    ld a, $96
    ld [hli], a  ; Set the laser's x position just to the left of the computer's paddle
    ; Computer has to wait awhile before firing another laser
    ld a, LASER_COOLDOWN
    ld [wComputerLaserCooldown], a
    ret
.done
    ; Decrement the cooldown counter
    ld a, [wComputerLaserCooldown]
    and a
    ret z
    dec a
    ld [wComputerLaserCooldown], a
    ret

HandleLaserCollisions:
    call HandlePlayerLaserCollisions
    jp HandleComputerLaserCollisions

HandlePlayerLaserCollisions:
    ld hl, wPlayerLasers
    ld b, MAX_LASERS + 1
.loop
    dec b
    ret z
    ld a, [hli]
    and a
    jr nz, .activeLaser
    inc hl
    inc hl
    inc hl
    inc hl  ; Move to next laser struct
    jr .loop
.activeLaser
    push hl
    ; Check if laser is moving the opposite direction of the pong ball
    ld a, [wBallXSpeed + 1]
    cp $80
    jr c, .checkForWall
    ; Check if laser is hitting the pong ball
    inc hl
    ld a, [hl]  ; Y position of laser (high byte)
    ld c, a
    ld a, [wBallY + 1]
    cp c
    jr c, .laserYIsGreater
    sub c
    jr .gotYDifference
.laserYIsGreater
    ld d, a
    ld a, c
    sub d
.gotYDifference
    ; a contains difference between laser and ball y coordinates
    cp 7  ; TODO: make this a constant
    jr nc, .checkForWall
    inc hl
    inc hl
    ld a, [hl]  ; X position of laser (high byte)
    ld c, a
    ld a, [wBallX + 1]
    cp c
    jr c, .laserXIsGreater
    sub c
    jr .gotXDifference
.laserXIsGreater
    ld d, a
    ld a, c
    sub d
.gotXDifference
    ; a contains difference between laser and ball x coordinates
    cp 7  ; TODO: make this a constant
    jr nc, .checkForWall
    ; Laser is hitting ball!
    ; Deactivate laser and change the ball's direction/speed
    pop hl
    dec hl
    xor a
    ld [hl], a  ; deactivate laser
    inc hl
    inc hl
    inc hl
    inc hl
    inc hl
    call IncreaseBallYSpeed
    call FlipBallDirection
    jr .loop
.checkForWall
    pop hl
    ; Check if laser is past the computer's wall
    inc hl
    inc hl
    inc hl
    ld a, [hl]  ; X position (high byte)
    cp 164
    jr c, .checkForPaddle
    ; Set laser to inactive
    push hl
    dec hl
    dec hl
    dec hl
    dec hl
    xor a
    ld [hl], a
    pop hl
    inc hl
    jr .loop
.checkForPaddle
    ; a contains x position
    cp 156
    jr nc, .continue
    cp 152
    jr c, .continue
    dec hl
    dec hl
    ld a, [hl]  ; high byte of laser's y position
    ld c, a
    ld a, [wComputerY + 1]
    cp c
    inc hl
    inc hl
    jr nc, .continue
    ld d, a
    ld a, [wComputerHeight]
    add d
    cp c
    jr c, .continue
    ; Laser is colliding with computer's paddle
    push hl
    dec hl
    dec hl
    dec hl
    dec hl
    xor a
    ld [hli], a  ; Deactivate laser
    call LaserHitComputerPaddle
    pop hl
.continue
    inc hl
    jp .loop

LaserHitComputerPaddle:
; Shrink the paddle.
    ld a, [wComputerY + 1]
    ld b, a
    ld a, [wComputerHeight]
    sub 4
    inc b
    inc b
    cp MIN_PADDLE_HEIGHT
    jr nc, .done
    dec b
    dec b
    ld a, MIN_PADDLE_HEIGHT
.done
    ld [wComputerHeight], a
    ld a, b
    ld [wComputerY + 1], a
    ret

HandleComputerLaserCollisions:
    ld hl, wComputerLasers
    ld b, MAX_LASERS + 1
.loop
    dec b
    ret z
    ld a, [hli]
    and a
    jr nz, .activeLaser
    inc hl
    inc hl
    inc hl
    inc hl  ; Move to next laser struct
    jr .loop
.activeLaser
    push hl
    ; Check if laser is moving the opposite direction of the pong ball
    ld a, [wBallXSpeed + 1]
    cp $80
    jr nc, .checkForWall
    ; Check if laser is hitting the pong ball
    inc hl
    ld a, [hl]  ; Y position of laser (high byte)
    ld c, a
    ld a, [wBallY + 1]
    cp c
    jr c, .laserYIsGreater
    sub c
    jr .gotYDifference
.laserYIsGreater
    ld d, a
    ld a, c
    sub d
.gotYDifference
    ; a contains difference between laser and ball y coordinates
    cp 7  ; TODO: make this a constant
    jr nc, .checkForWall
    inc hl
    inc hl
    ld a, [hl]  ; X position of laser (high byte)
    ld c, a
    ld a, [wBallX + 1]
    cp c
    jr c, .laserXIsGreater
    sub c
    jr .gotXDifference
.laserXIsGreater
    ld d, a
    ld a, c
    sub d
.gotXDifference
    ; a contains difference between laser and ball x coordinates
    cp 7  ; TODO: make this a constant
    jr nc, .checkForWall
    ; Laser is hitting ball!
    ; Deactivate laser and change the ball's direction/speed
    pop hl
    dec hl
    xor a
    ld [hl], a  ; deactivate laser
    inc hl
    inc hl
    inc hl
    inc hl
    inc hl
    call IncreaseBallYSpeed
    call FlipBallDirection
    jr .loop
.checkForWall
    pop hl
    ; Check if laser is past the computer's wall
    inc hl
    inc hl
    inc hl
    ld a, [hl]  ; X position (high byte)
    cp 252
    jr c, .checkForPaddle
    ; Set laser to inactive
    push hl
    dec hl
    dec hl
    dec hl
    dec hl
    xor a
    ld [hl], a
    pop hl
    inc hl
    jr .loop
.checkForPaddle
    ; a contains x position
    cp 4
    jr c, .continue
    cp 8
    jr nc, .continue
    dec hl
    dec hl
    ld a, [hl]  ; high byte of laser's y position
    ld c, a
    ld a, [wPlayerY + 1]
    cp c
    inc hl
    inc hl
    jr nc, .continue
    ld d, a
    ld a, [wPlayerHeight]
    add d
    cp c
    jr c, .continue
    ; Laser is colliding with player's paddle
    push hl
    dec hl
    dec hl
    dec hl
    dec hl
    xor a
    ld [hli], a  ; Deactivate laser
    call LaserHitPlayerPaddle
    pop hl
.continue
    inc hl
    jp .loop

LaserHitPlayerPaddle:
; Shrink the paddle.
    ld a, [wPlayerY + 1]
    ld b, a
    ld a, [wPlayerHeight]
    sub 4
    inc b
    inc b
    cp MIN_PADDLE_HEIGHT
    jr nc, .done
    dec b
    dec b
    ld a, MIN_PADDLE_HEIGHT
.done
    ld [wPlayerHeight], a
    ld a, b
    ld [wPlayerY + 1], a
    ret

FlipBallDirection:
; Flips the x speed of the ball
    ld a, [wBallXSpeed]
    ld c, a
    ld a, [wBallXSpeed + 1]
    ld b, a
    call InvertBC
    ld a, c
    ld [wBallXSpeed], a
    ld a, b
    ld [wBallXSpeed + 1], a
    ret

IncreaseBallYSpeed:
; Makes ball's y speed faster
    ld a, [wBallYSpeed]
    ld c, a
    ld a, [wBallYSpeed + 1]
    ld b, a
    cp $80
    jr c, .movingDown
    ; ball is moving upward
    ld a, c
    sub BALL_Y_SPEED_DELTA
    jr nc, .noCarry
    dec b
.noCarry
    ld c, a
    ; bc is new speed
    ld a, b
    cp MIN_Y_SPEED
    jr nc, .saveSpeed
    ld b, MIN_Y_SPEED
    ld c, 0
    jr .saveSpeed
.movingDown
    ; ball is moving downward
    ld a, c
    add BALL_Y_SPEED_DELTA
    jr nc, .noCarry2
    inc b
.noCarry2
    ld c, a
    ; bc is new speed
    ld a, b
    cp MAX_Y_SPEED
    jr c, .saveSpeed
    ld b, MAX_Y_SPEED
    ld c, 0
.saveSpeed
    ; bc is the Y speed to save
    ld a, c
    ld [wBallYSpeed], a
    ld a, b
    ld [wBallYSpeed + 1], a
    ret

WaitForNextFrame:
    ld hl, VBlankFlag
    xor a
    ld [hl], a
.wait
    ld a, [hl]
    and a
    jr z, .wait
    ret

Main:
; Master control loop for the game.
    call RunCurrentScreen
    jr Main

RunCurrentScreen:
    ld a, [wCurrentScreen]
    rst $18  ; Call function in the following pointer table
ScreenFunctions:
    dw RunTitlescreen  ; SCREEN_TITLESCREEN
    dw RunGame         ; SCREEN_GAME

RunTitlescreen:
    ld a, [wScreenState]
    rst $18
TitlescreenFunctions:
    dw LoadTitlescreenGraphics
    dw MainTitlescreen

LoadTitlescreenGraphics:
    ld d, 1
    ld hl, vBGMap0
    ld bc, $400
    call ClearGfx
    call ClearOAMBuffer
    hlCoord 5, 8, vBGMap0
    ld d, h
    ld e, l
    ld hl, TitlescreenMainText
    call PrintText
    ; advance to next titlescreen state
    ld a, 1
    ld [wScreenState], a
    ret

TitlescreenMainText:
    db "LAZERPONG@"

MainTitlescreen:
; Main titlescreen loop.
; Go to the game when player pressed START or A
    ld a, [hJoypadState]
    bit BIT_A_BUTTON, a
    jr nz, .exitTitlescreen
    bit BIT_START, a
    jr z, .stayOnTitlescreen
.exitTitlescreen
    xor a
    ld [wScreenState], a
    ld a, SCREEN_GAME
    ld [wCurrentScreen], a
    ret
.stayOnTitlescreen
    jr MainTitlescreen

RunGame:
    ld a, [wScreenState]
    rst $18
GameFunctions:
    dw InitGame
    dw GameLoop

InitGame:
; Initializes paddles, lasers, ball, etc.
    call ResetScores
    call InitPlayerPaddle
    call InitPlayerLasers
    call InitComputerPaddle
    call InitComputerLasers
    call InitBall
    ld a, START_PLAY_TIME
    ld [wStartPlayTimer], a
    ld d, 1
    ld hl, vBGMap0
    ld bc, $400
    call ClearGfx
    ld a, 1
    ld [wScreenState], a  ; Advance to GameLoop state
    ret

GameLoop:
; Main game loop.
    call WaitForNextFrame
    call MovePlayerPaddle
    call MoveComputerPaddle
    ld a, [wStartPlayTimer]
    and a
    jr z, .currentlyPlaying
    dec a
    ld [wStartPlayTimer], a
    ret
.currentlyPlaying
    call ShootLasers
    call MoveLasers
    call MoveBall
    call HandleLaserCollisions
    ret

MovePlayerPaddle:
; Moves the player's paddle up/down based on the buttons being pressed.
    ld a, [hJoypadState]
    bit BIT_D_UP, a
    jr nz, .pressingUp
    bit BIT_D_DOWN, a
    ret z
    ; pressing Down
    ld a, [wPlayerY]
    ld l, a
    ld a, [wPlayerY + 1]
    ld h, a
    ld bc, BASE_PADDLE_DOWN_SPEED
    add hl, bc
    push hl
    ; Check if the new paddle position is hitting the bottom of the screen
    ld a, [wPlayerHeight]
    add h
    cp 144 + 1  ; Bottom of the screen (pixels)
    pop hl
    jr c, .savePosition
    ; Set the paddle's position so it's touching the bottom of the screen
    sub h
    ld b, a  ; Save paddle height into b
    ld a, 144
    sub b
    ld h, a
    ld l, 0
    jr .savePosition
.pressingUp
    ld a, [wPlayerY]
    ld l, a
    ld a, [wPlayerY + 1]
    ld h, a
    ld bc, BASE_PADDLE_UP_SPEED
    add hl, bc
    ; Check if the new paddle position it hitting the top of the screen
    ld a, h
    cp 220  ; Arbitrary large number. We're just checking if the y position had underflow.
    jr c, .savePosition
    ; Set the paddle's position so it's touching the top of the screen
    ld hl, $0000
.savePosition
    ld a, l
    ld [wPlayerY], a
    ld a, h
    ld [wPlayerY + 1], a
    ret

MoveComputerPaddle:
    ld a, [wBallY + 1]
    sub 8
    ld [wComputerY + 1], a
    ret


SECTION "Bank 1",ROMX,BANK[$1]

GameGfx:
    INCBIN "gfx/game.2bpp"
