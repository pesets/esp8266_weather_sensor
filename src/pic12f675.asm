	list p=12f675		;сообщаем ассемблеру используемый чип
	include "p12f675.inc"	;загружаем настройки по умолчанию и константы для данного чипа
				;устанавливаем конфигурацию чипа
	__config _INTRC_OSC_NOCLKOUT & _WDT_ON & _PWRTE_OFF & _BODEN_OFF & _MCLRE_OFF & _CPD_OFF & _CP_OFF

; переменные (регистры)
	cblock	0x20
	d1
	d2
	d3
	cfg
	AARGB0
	AARGB1
	AARGB2
	BARGB0
	BARGB1       
	LOOPCOUNT
	REMB0
	REMB1         
	endc

;Макрос умножения 16 битное число на 8 битное число
;-------------------------------------------------------------------------
; 16bit by 8bit unsigned multiply
;  by Martin Sturm 2010
; tested
;
; aH:aL * b --> r3:r2:r1
;
; 69 instructions, 69 cycles
;

; helper macro
mmac MACRO A,bit, u2,u1
	BTFSC	A,bit
	ADDWF	u2,F
	RRF	u2,F
	RRF	u1,F
	ENDM
	
MULT_16x8_FASTEST MACRO aH,aL, b, r3,r2,r1

	CLRF	r3
	CLRF	r1
	CLRC
	MOVFW	b	; comment out if 8bit multiplicand already in W
			;  also, b can be removed from macro arguments
	mmac	aL,0, r3,r1
	mmac	aL,1, r3,r1
	mmac	aL,2, r3,r1
	mmac	aL,3, r3,r1
	mmac	aL,4, r3,r1
	mmac	aL,5, r3,r1
	mmac	aL,6, r3,r1
	mmac	aL,7, r3,r1
	
	CLRF	r2
	; carry already clear from last RRF of mmac above
	; 8bit multiplicand still in W
	mmac	aH,0, r3,r2
	mmac	aH,1, r3,r2
	mmac	aH,2, r3,r2
	mmac	aH,3, r3,r2
	mmac	aH,4, r3,r2
	mmac	aH,5, r3,r2
	mmac	aH,6, r3,r2
	mmac	aH,7, r3,r2
	ENDM

	org	0x0000		; задаем адрес начала программы
Main
; первичная инициализация
	bsf	STATUS, RP0	; переключение на банк 1
	call	0x3ff		; получаем в W калибровочную константу внутреннего RC генератора
	movwf	OSCCAL		; калибруем внутренний RC генератор
	
	movlw	b'01010100'     ; задаем частоту АЦП 1:16, канал GP2 - аналоговый вход
	movwf	ANSEL		; 
	
	bcf	STATUS, RP0	; переключение на банк 0
	movlw	b'10001001'     ; включаем модуль АЦП, у результата - правое выравнивание, 
	movwf	ADCON0		; опорное напряжение - Vdd, канал AN2, АЦП пока не стартуем
	
	movlw	b'00000111'     ; выключаем компаратор
	movwf	CMCON		; 

	bsf	STATUS, RP0	; переключение на банк 1
	clrf	VRCON		; выключаем источник опорного напряжения компаратора
	
	movlw	b'00111101'     ; выбираем направления: GP1 - выход, остальные - входы
	movwf	TRISIO		; 

	movlw	b'00001111'     ; задаем значения предделителя WDT равное 1:128 и
	movwf	OPTION_REG	; разрешаем использование внутренних подтягивающих резисторов
	
	movlw	b'00000001'	; используем подтягивающий резистор для GP<0>
	movwf	WPU		; 

	bcf	STATUS, RP0	; переключение на банк 0
	clrf	GPIO		; устанавливаем все выходы GPIO в ноль
 	clrwdt			; очищаем счетчик WDT

; попытка выяснить причину запуска
	bsf	STATUS, RP0	; переключение на банк 1
        btfsc	PCON, NOT_POR	; если был сброс по питанию, то пропустить следующую команду
        goto	Reset_by_WDT	; все остальные сбросы считаем от WDT
	bsf	PCON, NOT_POR	; очистить флаг сброса по питанию

; чтение перемычек
	bsf	STATUS, RP0	; переключение на банк 1
	movlw	b'00110001'	; используем подтягивающие резисторы для GP<5,4,0>
	movwf	WPU		; устанавливаем подтягивающие резисторы
	
	bcf	STATUS, RP0	; переключение на банк 0
	movlw	0		; w = 0
        btfsc	GPIO, 4		; пропустить следующую команду если GP<4> == 0
	addlw	1               ; w = w + 1
        btfsc	GPIO, 5		; пропустить следующую команду если GP<5> == 0
	addlw	2		; w = w + 2
	movwf	cfg		; cfg = w
	
	bsf	STATUS, RP0	; переключение на банк 1
	movlw	b'00000001'	; используем подтягивающий резистор только для GP<0>
	movwf	WPU		; 


	
; главный цикл программы

Loop
	bcf	STATUS, RP0	; переключение на банк 0
	bsf 	GPIO, 1		; подаем 1 на выход GP1
	movlw	b'00110000'	; настраиваем таймер 1, делитель 1:8, таймер пока выключен
	movwf	T1CON           ;
	clrf	TMR1L           ; сбрасываем счетчик
	clrf	TMR1H           ; таймера 1
	bcf	PIR1, 0         ; и флаг переполнения таймера 1
	movlw	b'00110001'	; запускаем таймер 1
	movwf	T1CON           ;
	movlw	0x13            ; если таймер 1 переполнится 19 раз,
	movwf	LOOPCOUNT       ; то это значит, что прошло примерно 10 сек.

;начало цикла ожидания 0 на GP<0> от внешнего контроллера
Wait0                            
	clrwdt			; очищаем счетчик WDT
	call	Check10sTimeOut ; проверяем, не прошло ли 10 сек
        btfss	GPIO, 0         ; пропустить следующую команду, если GP<0> == 1
        goto	$+2             ; GP<0> == 0, перепрыгиваем через следующую команду
	goto	Wait0           ; переход на начало цикла

	bsf	ADCON0, 1	; запускаем АЦП
WaitADC
 	clrwdt			; очищаем счетчик WDT
	btfsc   ADCON0, 1	; пропустить следующую команду, если АЦП закончил
	goto	WaitADC		; переход на начало цикла

        movf	ADRESH, w       ;
	movwf	AARGB0          ; AARGB0 = старший байт результата АЦП
	bsf	STATUS, RP0	; переключение на банк 1
        movf	ADRESL, w       ;
	bcf	STATUS, RP0	; переключение на банк 0
	movwf	AARGB1          ; AARGB1 = младший байт результата АЦП
        movf	cfg, w          ;
	movwf	d1              ;
	clrc                    ;
	rlf	d1, f           ;
	rlf	d1, w           ;
	iorwf	AARGB0, f       ; AARGB0 = AARGB0 or (cfg << 2)

	movf	AARGB0, w       ;
	movwf	AARGB2          ;
	movf	AARGB1, w       ;
	addwf	AARGB2, f       ;
	incf	AARGB2, f       ;
	incf	AARGB2, f       ; AARGB2 = AARGB0 + AARGB1 + 2

	clrf	d1              ; подготавливаем счетчик цикла, который покажет, сколько на GP<0>
	movlw	0x1A            ; держался 0. d2:d1 = 0x1A00. 
	movwf	d2              ; максимальное время 0x1A00 * 6 = примерно 40000 мкс.
Wait1	
	btfsc	GPIO, 0         ; такты 1, 2. пропустить следующую коменду, если GP<0> == 0
	goto	CheckTime       ; на GP<0> появилась 1, выходим из цикла
	clrwdt			; такт 3. очищает WDT
	incfsz	d1, f           ; такт 4. d1 = d1 + 1, проверяем на переполнение d1
	goto	Wait1           ; такты 5 6. d1 не переполнилась, продолжаем цикл
	decfsz  d2, f		; d2 = d2 - 1, проверяем на обнуление d2
	goto	Wait1		; d2 не обнулилась, продолжаем цикл
	bcf 	GPIO, 1		; 0 держался более 40000 мкс. снимаем питание с контроллера
	goto    Wait0		; на начало программы
; проверка времени, в течение которого на GP<0> был 0
CheckTime
	subwf	d2, w           ;
	skpz                    ;
	goto	SendData        ; если d2:d1 < 128, то 0 на GP<0> был слишком мало
	btfss	d1, 7           ; т.е. 127*6 = 762 мкс - это минимально небходымое время
	goto	Wait0           ; игнорируем такой 0 и переходим на начало программы

; контроллер выдал сигнал на готовность получения данных
SendData
	bsf	STATUS, RP0	; переключение на банк 1
	bcf	TRISIO, 0       ; переключаем GP<0> на выход
	bcf	STATUS, RP0	; переключение на банк 0
	bsf	GPIO, 0         ; GP<0> = 1
	call	Wait20us        ; ждем 20 мкс.
	bcf	GPIO, 0         ; GP<0> = 0
	call	Wait20us        ; ждем 80 мкс.
	call	Wait20us        ;
	call	Wait20us        ;
	call	Wait20us        ;
	bsf	GPIO, 0         ; GP<0> = 1
	call	Wait20us        ; ждем 80 мкс.
	call	Wait20us        ;
	call	Wait20us        ;
	call	Wait20us        ;
	bcf	GPIO, 0         ; GP<0> = 0
	call	Wait20us        ; ждем 46 мкс.
	call	Wait20us        ;
	goto	$+1             ;
	goto	$+1             ;
	goto	$+1             ;
	movf	AARGB0, w       ;
	call	SendByte        ; посылаем 1-й байт
	movf	AARGB1, w       ;
	call	SendByte        ; посылаем 2-й байт
	movf	AARGB2, w       ;
	call	SendByte        ; посылаем 3-й байт
	bsf	GPIO, 0         ; GP<0> = 1
	bsf	STATUS, RP0	; переключение на банк 1
	bsf	TRISIO, 0       ; переключаем GP<0> на вход
	bsf	WPU, 0		; устанавливаем подтягивающий резистор к GP<0>
	bcf	STATUS, RP0	; переключение на банк 0
	goto	Wait0	        ; переход на начало программы

; функция посылки байта. байт в W
SendByte
	movwf	d2		; d2 = W
	movlw	8		;
	movwf	d3		; d3 = 8 (счетчик бит)
SendByte_0
	bsf	GPIO, 0		; GP<0> = 1
	call	Wait20us        ; ждем 26 мкс. 
	goto	$+1             ;
	rlf	d2, f           ; сдвигаем старший бит из d2 в флаг C
	skpc                    ; если С установлен, то пропускает следующую команду 
	goto	SendByte_1      ;
	call	Wait20us        ; ждем еще 44 мкс.
	call	Wait20us	;
	goto	$+1
	goto	$+1
SendByte_1                      
	bcf	GPIO, 0         ; GP<0> = 0
	call	Wait20us        ; ждем 49 мкс.
	call	Wait20us        ; 
	goto	$+1             ;
	goto	$+1             ;
	goto	$+1             ;
	decfsz  d3, f           ;
	goto	SendByte_0      ; выводим следующий бит
	return

;функция ожидания 20 мкс.
Wait20us
	movlw	0x05
	movwf	d1
Wait20us_0
	decfsz	d1, f
	goto	Wait20us_0
	return

;функция проверки окончания 10 сек. интервала
Check10sTimeOut
	btfss	PIR1, 0		; флаг переполнения таймера 1 установлен?
	return                  ; нет - выходим из функции
	bcf	PIR1, 0         ; снимает флаг переполнения таймера 1
	decfsz  LOOPCOUNT, f	; уменьшаем переменную цикла и проверяем её на 0
	return			; нет - выходим из функции

	movf	cfg, w		; w = cfg (состояние перемычек)
        movwf	d3		; d1 = w
	incf	d3, f		; d1 = d1 + 1
	
	decfsz  d3, f		; d1 = d1 - 1, пропуск следующей команды, если d1 == 0
	goto	Not_0		; d1 != 0, переходим к следующей проверке
	bsf 	GPIO, 1		; перемычки == 00. подаем 1 на выход GP<1>
	return	                ; и выходим из функции
Not_0	
	bcf 	GPIO, 1		; подаем 0 на выход GP<1>
	decfsz  d3, f		; d1 = d1 - 1, пропуск следующей команды, если d1 == 0
	goto	Not_01		; d1 != 0, переходим к следующей проверке
	movlw	0               ; перемычки == 01
	movwf	d1              ;
	movlw	0x32            ; d1:d2 = 50 сек (время сна)
	movwf	d2              ;
	goto	Wait_WDT        ; уходим калибровать WDT и спать
Not_01
	decfsz  d3, f		; d1 = d1 - 1, пропуск следующей команды, если d1 == 0
	goto	Not_012		; d1 != 0, значит перемычки == 11
	movlw	0x01            ; перемычки == 10
	movwf	d1              ;
	movlw	0x22            ; d1:d2 = 290 сек (время сна)
	movwf	d2              ;
	goto	Wait_WDT        ; уходим калибровать WDT и спать
Not_012                         ; перемычки == 11
	movlw	0x02            ;
	movwf	d1              ; d1:d2 = 590 сек (время сна)
	movlw	0x4E            ;
	movwf	d2              ;
Wait_WDT                        ; калибровка WDT и подготовка ко сну
	clrf	T1CON           ; останавливает таймер 1
	clrf	TMR1H           ; и очищаем его счетчик
	clrf	TMR1L           ;
	bsf	STATUS, RP0	; переключение на банк 1
	movlw	b'00001001'     ; задаем значения предделителя WDT равное 1:2 и
	movwf	OPTION_REG	; 
	bcf	STATUS, RP0	; переключение на банк 0
        clrwdt                  ; сбрасываем счетчик WDT
	movlw	1               ;
	movwf	T1CON           ; запускаем таймер 1
Inf_Loop
	goto Inf_Loop           ; ждем, когда нас убъет WDT
	

; точка входа при сбросе по WDT
Reset_by_WDT
	bsf	PCON, NOT_POR	; очистить флаг сброса по питанию
	bcf	STATUS, RP0	; переключение на банк 0
	movf	TMR1H, w        ;
	movwf	BARGB0          ;
	movf	TMR1L, w        ;
	movwf	BARGB1          ; BARGB0:BARGB1 = счетчик таймера 1
	movlw	0x0F            ;
	movwf	AARGB0          ;
	movlw	0x42            ;
	movwf	AARGB1          ;
	movlw	0x40            ;
	movwf	AARGB2          ; AARGB0:AARGB1:AARGB2 = 1000000
	call	FXD2416U        ; 
	movf	AARGB2, w       ; 
	movwf	d3              ; d3 = 1000000 / счетчик таймера 1
	MULT_16x8_FASTEST d1, d2, d3, AARGB0, AARGB1, AARGB2
	clrf	BARGB0          ; AARGB0:AARGB1:AARGB2 = d1:d2 * d3
	movlw	0x40            ;
	movwf	BARGB1          ; BARGB1 = 64
	call	FXD2416U        ; AARGB2 = AARGB0:AARGB1:AARGB2 / 64
; готовимся ко сну					
	bsf	STATUS, RP0	; переключение на банк 1
	movlw	b'00001111'     ; задаем значения предделителя WDT равное 1:128
	movwf	OPTION_REG	; 

	movlw	b'00000000'	; убираем все подтягивающие резисторы
	movwf	WPU		; 
	
	bcf	STATUS, RP0	; переключение на банк 0
	movlw	b'10001000'     ;	
	movwf	ADCON0		; включаем модуль АЦП
	
	clrf	T1CON		; останавливаем таймер 1

Delay_X_Loop
	clrwdt			; очищаем счетчик WDT
	sleep			; спим примерно 3.3 сек
	decfsz	AARGB2, f	; AARGB2 = AARGB2 - 1, пропуск следующей команды, если AARGB2 == 0
	goto	Delay_X_Loop    ; переход на начало цикла

	movlw	b'10001001'     ;	
	movwf	ADCON0		; включаем модуль АЦП
	
	bsf	STATUS, RP0	; переключение на банк 1
	movlw	b'00000001'	; используем подтягивающий резистор для GP<0>
	movwf	WPU		; 


	goto	Loop            ; переходим на начало программы


; Функция деления 24 битного числа на 16 битное
;Inputs:
;   Dividend - AARGB0:AARGB1:AARGB2 (0 - most significant!)
;   Divisor  - BARGB0:BARGB1
;Temporary:
;   Counter  - LOOPCOUNT
;   Remainder- REMB0:REMB1
;Output:
;   Quotient - AARGB0:AARGB1:AARGB2
;
FXD2416U:
	CLRF	REMB0
        CLRF	REMB1
        MOVLW	.24
        MOVWF	LOOPCOUNT
LOOPU2416
        RLF	AARGB2, W           ;shift dividend left to move next bit to remainder
        RLF	AARGB1, F           ;
        RLF	AARGB0, F           ;

        RLF	REMB1, F            ;shift carry (next dividend bit) into remainder
        RLF	REMB0, F

        RLF	AARGB2, F           ;finish shifting the dividend and save  carry in AARGB2.0,
                                ;since remainder can be 17 bit long in some cases
                                ;(e.g. 0x800000/0xFFFF). This bit will also serve
                                ;as the next result bit.
         
        MOVF	BARGB1, W          ;substract divisor from 16-bit remainder
        SUBWF	REMB1, F          ;
        MOVF	BARGB0, W          ;
        BTFSS	STATUS, C         ;
        INCFSZ	BARGB0, W        ;
        SUBWF	REMB0, F          ;

;here we also need to take into account the 17th bit of remainder, which
;is in AARGB2.0. If we don't have a borrow after subtracting from lower
;16 bits of remainder, then there is no borrow regardless of 17th bit 
;value. But, if we have the borrow, then that will depend on 17th bit 
;value. If it is 1, then no final borrow will occur. If it is 0, borrow
;will occur. These values match the borrow flag polarity.

        SKPNC                  ;if no borrow after 16 bit subtraction
        BSF AARGB2, 0          ;then there is no borrow in result. Overwrite
                                ;AARGB2.0 with 1 to indicate no
                                ;borrow.
                                ;if borrow did occur, AARGB2.0 already
                                ;holds the final borrow value (0-borrow,
                                ;1-no borrow)

        BTFSC AARGB2, 0         ;if no borrow after 17-bit subtraction
        GOTO UOK46LL           ;skip remainder restoration.

        ADDWF REMB0, F          ;restore higher byte of remainder. (w 
                                ;contains the value subtracted from it
                                ;previously)
        MOVF BARGB1, W          ;restore lower byte of remainder
        ADDWF REMB1, F          ;

UOK46LL

        DECFSZ LOOPCOUNT, f     ;decrement counter
        GOTO LOOPU2416         ;and repeat the loop if not zero.

        RETURN

	end